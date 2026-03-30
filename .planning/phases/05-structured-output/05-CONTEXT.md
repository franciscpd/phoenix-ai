# Phase 5: Structured Output - Context

**Gathered:** 2026-03-30
**Status:** Ready for planning

<domain>
## Phase Boundary

JSON schemas can be declared as plain Elixir maps or as modules implementing `PhoenixAI.Schema` behaviour (Plug-like dual interface). Provider adapters translate the schema to provider-specific structured output parameters (OpenAI `response_format`, Anthropic forced tool_use). Responses are validated against the schema before being returned, with field-level error detail on failure.

</domain>

<decisions>
## Implementation Decisions

### Schema Definition (Dual Interface)
- **D-01:** Schema accepts BOTH plain maps AND modules implementing `PhoenixAI.Schema` behaviour. Pattern match on argument type dispatches accordingly — same pattern as Plug (module or function).
- **D-02:** Plain map format is identical to `Tool.parameters_schema/0` — atom keys, JSON Schema structure: `%{type: :object, properties: %{...}, required: [...]}`. Reuses existing `to_json_schema/1` conversion.
- **D-03:** `PhoenixAI.Schema` behaviour defines `schema/0` callback (required) returning the same map format. Additional callbacks are Claude's discretion (e.g., optional `cast/1` for custom transformation).
- **D-04:** Plain maps are for quick prototyping. Behaviour modules are for reusable, documented, production schemas. Both produce identical provider output.

### API Surface
- **D-05:** Schema is passed via `:schema` option — `AI.chat(msgs, schema: MyApp.Sentiment)` or `AI.chat(msgs, schema: %{...})`. Provider-agnostic naming, not tied to OpenAI's `response_format`.
- **D-06:** New `parsed: map() | nil` field added to `%Response{}` struct. `content` keeps the raw JSON string, `parsed` holds the decoded + validated map. `nil` when no schema was provided.
- **D-07:** Schema works with `Agent.prompt/2` — Agent accepts `:schema` in `start_link/1` opts. Every response from the Agent includes `parsed` when schema is configured.
- **D-08:** Schema and tools coexist — tools run in the tool loop, schema validates the final response only. Both can be passed simultaneously.

### Provider Translation
- **D-09:** OpenAI adapter translates schema to `response_format: %{"type" => "json_schema", "json_schema" => %{"name" => "...", "schema" => ...}}` in the request body. Native structured output support.
- **D-10:** OpenRouter adapter uses same format as OpenAI (API-compatible).
- **D-11:** Anthropic adapter implements structured output via forced tool_use — creates an internal `"structured_output"` tool whose `input_schema` is the user's schema, with `tool_choice: %{"type" => "any"}`. The adapter extracts the tool_use input as the parsed response.
- **D-12:** When schema + tools coexist on Anthropic, the `"structured_output"` tool is appended to the user's tool list. `tool_choice` remains `"auto"`. The tool loop runs normally; when the model calls `structured_output`, the adapter extracts its input as parsed data.

### Validation
- **D-13:** Validation happens after JSON decode, before returning `{:ok, %Response{}}`. If validation fails, returns `{:error, {:validation_failed, details}}` with field-level detail (missing_keys, extra_keys, type_errors). Never silently passes — per SCHEMA-04.
- **D-14:** When response is not valid JSON (model returned free text), returns `{:error, {:invalid_json, raw_content}}`. Distinct from `:validation_failed` which means valid JSON but wrong shape.
- **D-15:** Validation scope for v1: required keys presence, basic types (string, number, integer, boolean, array, object), enum values, and recursive nested object validation. NOT included: min/max, pattern/regex, allOf/oneOf/$ref.
- **D-16:** No automatic retry on validation failure — consumer decides whether to retry. Keeps the library predictable and avoids hidden API cost.

### Claude's Discretion
- Whether `PhoenixAI.Schema` behaviour includes optional `cast/1` callback or stays with just `schema/0`
- Internal module for schema validation logic (e.g., `PhoenixAI.Schema.Validator`)
- How the `"structured_output"` synthetic tool name is generated/namespaced to avoid collision with user tools
- Exact structure of the validation error details map
- How schema option flows through ToolLoop (strip before provider call, validate after)
- Test fixture design for structured output round-trips

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Prior Phase Context
- `.planning/phases/01-core-foundation/01-CONTEXT.md` — D-05: call-site config cascade, D-09: Provider behaviour with @optional_callbacks, D-12: Mox testing strategy
- `.planning/phases/03-tool-calling/03-CONTEXT.md` — D-05/D-06/D-07: Schema format and to_json_schema/1 conversion, D-12: ToolLoop design (reused for schema+tools coexistence)
- `.planning/phases/04-agent-genserver/04-CONTEXT.md` — D-01/D-02: Agent start_link opts pattern, D-17: Agent delegates to ToolLoop

### Existing Code (schema-relevant)
- `lib/phoenix_ai/tool.ex` — `to_json_schema/1` and `deep_stringify/1` — reusable for schema conversion
- `lib/phoenix_ai/response.ex` — `%Response{}` struct to be extended with `parsed:` field
- `lib/phoenix_ai/providers/openai.ex` — `maybe_put/3` pattern for adding optional body params, `chat/2` body construction
- `lib/phoenix_ai/providers/anthropic.ex` — `format_tools/1` and tool_use content block parsing — pattern for synthetic structured_output tool
- `lib/ai.ex` — `run_with_tools/3` dispatch — needs extension for schema handling
- `lib/phoenix_ai/agent.ex` — Agent GenServer opts and delegation to ToolLoop
- `lib/phoenix_ai/provider.ex` — Provider behaviour definition

### Provider API Docs (structured output specifics)
- OpenAI Structured Outputs: `https://platform.openai.com/docs/guides/structured-outputs`
- Anthropic Tool Use (for forced tool_use pattern): `https://docs.anthropic.com/en/docs/build-with-claude/tool-use`

### Project Research
- `.planning/research/ARCHITECTURE.md` — Provider behaviour contract, adapter responsibilities
- `.planning/research/PITFALLS.md` — Relevant pitfalls for structured output design

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `PhoenixAI.Tool.to_json_schema/1` + `deep_stringify/1` — atom-to-string schema conversion, directly reusable for structured output schema translation
- `PhoenixAI.Tool.name/1`, `description/1` pattern — delegate functions for behaviour modules, same pattern for Schema
- OpenAI `maybe_put/3` — conditionally add body params, used to inject `response_format` when schema present
- Anthropic `format_tools/1` — envelope structure for creating the synthetic `structured_output` tool
- Anthropic `extract_tool_calls/1` — content block parsing to extract tool_use input as parsed data

### Established Patterns
- Behaviours for contracts (`PhoenixAI.Provider`, `PhoenixAI.Tool`) — `PhoenixAI.Schema` follows same pattern
- `@optional_callbacks` for non-required callbacks (used in Provider)
- Keyword list options flowing through the system (call-site > config > env)
- Each adapter owns its wire format translation — no shared injection code
- `%Response{}` struct as unified return type across all providers

### Integration Points
- `AI.chat/2` `run_with_tools/3` needs schema-aware dispatch
- `Response` struct needs new `parsed:` field
- Each adapter's `chat/2` needs schema-to-provider-format translation in body building
- `Agent` start_link opts need `:schema` support, passed through to ToolLoop/chat
- ToolLoop may need awareness of schema for Anthropic's synthetic tool approach

</code_context>

<specifics>
## Specific Ideas

- Dual interface (map + behaviour) follows the Plug pattern — idiomatic Elixir, familiar to Phoenix developers
- Schema map format identical to Tool.parameters_schema — zero learning curve for anyone who's already defined tools
- Anthropic's forced tool_use approach is the most reliable structured output strategy — it's what laravel/ai and other libraries use
- The `parsed` field on Response keeps backward compatibility — existing code using `content` is unaffected
- Validation is intentionally not exhaustive (no min/max, pattern, $ref) — covers 90% of use cases without pulling in a JSON Schema validation library

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 05-structured-output*
*Context gathered: 2026-03-30*
