# Phase 5: Structured Output — Design Spec

**Date:** 2026-03-30
**Status:** Approved
**Context:** `.planning/phases/05-structured-output/05-CONTEXT.md`

## Overview

JSON schemas can be declared as plain Elixir maps or as modules implementing `PhoenixAI.Schema` behaviour (Plug-like dual interface). Provider adapters translate the schema to their native structured output mechanism. Responses are validated against the schema before returning, with field-level error detail on failure.

**Requirements covered:** SCHEMA-01, SCHEMA-02, SCHEMA-03, SCHEMA-04

## Architecture: Centralized Validation in `AI.chat/2`

Validation happens at a single point — `AI.chat/2` — after the provider/ToolLoop returns. Each adapter only translates schema to its wire format. The validator is a pure-function module.

```
AI.chat/2
  ├── resolve schema (map or behaviour module)
  ├── extract JSON Schema map via PhoenixAI.Schema.resolve/1
  ├── pass schema_json to adapter via opts
  ├── adapter.chat/2 injects into body (response_format / synthetic tool)
  ├── ToolLoop.run or provider.chat (no schema awareness)
  └── decode JSON → validate → optional cast → populate Response.parsed
```

## Modules and Responsibilities

### `PhoenixAI.Schema` — Behaviour + Dual Resolution

Behaviour with `schema/0` callback (required) and `cast/1` (@optional_callback). Contains `resolve/1` that accepts map or module and returns string-keyed JSON Schema.

```elixir
defmodule PhoenixAI.Schema do
  @callback schema() :: map()
  @callback cast(data :: map()) :: {:ok, term()} | {:error, term()}
  @optional_callbacks [cast: 1]

  @spec resolve(module() | map()) :: map()
  def resolve(mod) when is_atom(mod), do: deep_stringify(mod.schema())
  def resolve(map) when is_map(map), do: deep_stringify(map)

  # Reuses same deep_stringify logic as PhoenixAI.Tool
  # (consider extracting shared helper or calling Tool's version)
end
```

**Usage:**

```elixir
# Plain map (quick prototyping):
AI.chat(msgs, schema: %{type: :object, properties: %{name: %{type: :string}}, required: [:name]})

# Behaviour module (production):
defmodule MyApp.Sentiment do
  @behaviour PhoenixAI.Schema

  @impl true
  def schema do
    %{
      type: :object,
      properties: %{
        sentiment: %{type: :string, enum: [:positive, :negative, :neutral]},
        confidence: %{type: :number}
      },
      required: [:sentiment, :confidence]
    }
  end
end

AI.chat(msgs, schema: MyApp.Sentiment)
```

### `PhoenixAI.Schema.Validator` — Pure Validation

Pure-function module. `validate(data, schema) :: :ok | {:error, details}`.

**Validation rules (v1 scope):**

| Check | Schema Input | Validation |
|-------|-------------|------------|
| Required | `required: [:name]` | Keys present in map |
| String | `type: :string` | `is_binary/1` |
| Number | `type: :number` | `is_number/1` |
| Integer | `type: :integer` | `is_integer/1` |
| Boolean | `type: :boolean` | `is_boolean/1` |
| Array | `type: :array` | `is_list/1` |
| Object | `type: :object` | `is_map/1` + recursive nested validation |
| Enum | `enum: [:a, :b]` | Value in list (string comparison) |

**Not included (v1):** `minimum`, `maximum`, `pattern`, `minItems`, `maxItems`, `allOf`, `oneOf`, `$ref`.

### `PhoenixAI.Response` — Extended Struct

```elixir
defstruct [:content, :parsed, :finish_reason, :model, tool_calls: [], usage: %{}, provider_response: %{}]
```

New field `parsed: map() | nil`. `nil` when no schema provided. Backward compatible.

## Data Flow

### Case 1: Schema without tools (OpenAI/OpenRouter)

1. `AI.chat/2` receives `schema:` option
2. `Schema.resolve(schema)` → string-keyed JSON Schema map
3. Pass `schema_json` and original `schema` (for cast) in opts
4. **OpenAI adapter** injects into body:
   ```json
   {"response_format": {"type": "json_schema", "json_schema": {"name": "structured_output", "strict": true, "schema": {...}}}}
   ```
5. Provider returns `{:ok, %Response{content: "{...}"}}`
6. `AI.chat/2` decodes JSON: `Jason.decode(content)`
   - Parse failure → `{:error, {:invalid_json, raw_content}}`
7. `Schema.Validator.validate(data, original_schema)`
   - Validation failure → `{:error, {:validation_failed, details}}`
8. Optional `cast/1` if schema is module with cast implemented
   - Cast failure → `{:error, {:cast_failed, reason}}`
9. Return `{:ok, %Response{content: raw_json, parsed: data}}`

### Case 2: Schema without tools (Anthropic)

Steps 1-2 same. Step 4 differs:

4. **Anthropic adapter** injects synthetic tool:
   ```json
   {"tools": [{"name": "structured_output", "description": "Return structured response matching the schema", "input_schema": {...}}], "tool_choice": {"type": "any"}}
   ```
5. Provider returns tool_use content block. Adapter's `parse_response/1`:
   - Detects `tool_use` with name `"structured_output"`
   - Extracts `input` as JSON string → puts in `Response.content`
   - Removes this tool_call from `Response.tool_calls` (so ToolLoop sees `[]`)
6-9 same as Case 1.

### Case 3: Schema + Tools (Anthropic)

4. Anthropic adapter appends synthetic tool to user's tool list:
   ```json
   {"tools": [{"name": "get_weather", ...}, {"name": "structured_output", ...}], "tool_choice": {"type": "auto"}}
   ```
   Note: `tool_choice: "auto"` (not `"any"`) to allow real tool calls.
5. ToolLoop runs normally — executes real tools, re-calls provider
6. When model calls `structured_output`: adapter extracts input, ToolLoop sees `tool_calls: []` → stops
7-9 same validation/cast flow

### Case 4: Schema + Tools (OpenAI)

4. OpenAI adapter injects `response_format` in body alongside `tools`
5. ToolLoop runs normally with tools
6. Final response (no more tool calls) has content as JSON matching schema
7-9 same validation flow

## Error Handling

Three distinct error types for structured output:

```elixir
# 1. Network/provider error (already exists — unchanged)
{:error, %PhoenixAI.Error{status: 429, message: "rate limit", provider: :openai}}

# 2. Response is not valid JSON
{:error, {:invalid_json, "Sure! Here's the sentiment analysis..."}}

# 3. Valid JSON but doesn't match schema
{:error, {:validation_failed, %{
  missing_keys: ["confidence"],
  type_errors: [%{key: "sentiment", expected: "string", got: "integer", value: 42}],
  enum_errors: [%{key: "sentiment", expected: ["positive", "negative", "neutral"], got: "maybe"}]
}}}

# 4. Cast function failed (only when behaviour module implements cast/1)
{:error, {:cast_failed, reason}}
```

No automatic retry on validation failure — consumer decides retry strategy. Keeps the library predictable and avoids hidden API costs.

## Agent Integration

Agent accepts `:schema` in `start_link/1` opts. Stored in GenServer state.

```elixir
# In Agent.init/1:
schema = Keyword.get(opts, :schema)
# ... store in state, drop from provider_opts
```

**Important:** The Agent calls `ToolLoop.run` and `provider_mod.chat` directly — it does NOT go through `AI.chat/2`. Therefore, the validation/decode/cast logic must be extracted into a shared helper (e.g., `PhoenixAI.Schema.validate_response/3`) that both `AI.chat/2` and `Agent.handle_info` can call after receiving the provider response.

```elixir
# Shared validation helper used by both AI.chat/2 and Agent:
# PhoenixAI.Schema.validate_response(response, schema, original_schema_input)
#   → {:ok, %Response{parsed: data}} | {:error, {:invalid_json, _}} | ...

# In Agent.handle_info (after Task completes):
result = case {schema, result} do
  {nil, result} -> result
  {schema, {:ok, response}} -> Schema.validate_response(response, schema, state.schema)
  {_, error} -> error
end
```

## Shared Code: `deep_stringify`

Both `PhoenixAI.Tool.to_json_schema/1` and `PhoenixAI.Schema.resolve/1` need `deep_stringify`. Options:

1. Extract to shared helper (e.g., `PhoenixAI.Util.deep_stringify/1`)
2. Keep duplicated (it's ~15 lines)
3. Schema calls `Tool.to_json_schema/1` internally

Decision: Claude's discretion. All options are acceptable for this scope.

## Testing Strategy

### New test files

| Test File | What it tests |
|-----------|--------------|
| `test/phoenix_ai/schema_test.exs` | Schema behaviour, resolve/1 (map and module), dual dispatch |
| `test/phoenix_ai/schema/validator_test.exs` | All validation checks — types, required, enum, nested, edge cases |
| `test/phoenix_ai/providers/openai_structured_test.exs` | OpenAI response_format injection in request body |
| `test/phoenix_ai/providers/anthropic_structured_test.exs` | Anthropic synthetic tool injection + tool_use extraction |
| `test/phoenix_ai/ai_structured_test.exs` | AI.chat/2 end-to-end with schema — decode, validate, parsed |
| `test/phoenix_ai/agent_structured_test.exs` | Agent.prompt/2 with schema option |

### Fixtures needed

```
test/fixtures/
├── openai_structured_response.json        # response with JSON content
├── anthropic_structured_response.json     # response with tool_use "structured_output"
├── anthropic_tools_and_schema.json        # response after tool loop + structured_output final
```

### Testing approach

- **Schema.Validator**: Pure unit tests — no Mox, no HTTP. Many edge cases (missing keys, wrong types, nested objects, enum, empty schema, null values)
- **Adapter translation**: Mox for provider.chat/2. Verify request body contains `response_format` (OpenAI) or synthetic tool (Anthropic)
- **AI.chat integration**: Mox. Verify full flow: schema resolve → adapter → validate → parsed in Response
- **Agent**: Mox with `Mox.set_mode({:global, self()})` as in previous phases

## Files Modified

### New files
- `lib/phoenix_ai/schema.ex` — Schema behaviour + resolve/1
- `lib/phoenix_ai/schema/validator.ex` — Pure validation module
- All test files listed above
- Fixture JSON files

### Modified files
- `lib/phoenix_ai/response.ex` — Add `:parsed` field
- `lib/phoenix_ai/providers/openai.ex` — Inject `response_format` when schema present
- `lib/phoenix_ai/providers/anthropic.ex` — Inject synthetic tool + extract from tool_use
- `lib/phoenix_ai/providers/openrouter.ex` — Same as OpenAI (response_format)
- `lib/ai.ex` — Schema-aware dispatch: resolve, pass to adapter, validate, populate parsed
- `lib/phoenix_ai/agent.ex` — Accept `:schema` opt, pass through

## Key Design Decisions Summary

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Schema interface | Map + behaviour (dual) | Plug-like pattern, idiomatic Elixir |
| Map format | Same as Tool.parameters_schema | Consistency, reuses to_json_schema |
| API option name | `:schema` | Provider-agnostic |
| Parsed location | `Response.parsed` field | Backward compatible, nil when unused |
| Anthropic strategy | Forced tool_use | Most reliable, no native support |
| Schema + tools (Anthropic) | Schema as extra tool | Single-pass, no extra API call |
| Synthetic tool logic | Inside adapter only | ToolLoop stays pure, adapter encapsulates |
| Validation location | Centralized in AI.chat/2 | Single point, adapters stay thin |
| Validation scope | Required + types + enum + nested | 90% coverage, no external deps |
| Retry on failure | No — consumer decides | Predictable, no hidden costs |
| Error granularity | 3 types: invalid_json, validation_failed, cast_failed | Clear distinction for consumers |

---

*Phase: 05-structured-output*
*Design approved: 2026-03-30*
