---
status: complete
phase: 05-structured-output
source: PLAN.md, git log 94926dc..080ae07
started: 2026-03-30T16:38:00Z
updated: 2026-03-30T16:58:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Schema declaration via plain map
expected: Passing a plain Elixir map as the `schema:` option to `AI.chat/2` resolves it into a string-keyed JSON Schema. The provider adapter receives the schema in its native wire format.
result: pass
evidence: SchemaTest — 4 tests pass (atom key conversion, nested objects, booleans, string/number preservation)

### 2. Schema declaration via behaviour module
expected: Defining a module with `@behaviour PhoenixAI.Schema` and implementing `schema/0` works as the `schema:` option. `PhoenixAI.Schema.resolve/1` calls `mod.schema()` and deep-stringifies the result.
result: pass
evidence: SchemaTest — "resolve/1 with behaviour module calls schema/0 and converts to string keys" + schema_map/1 tests pass

### 3. Schema.Validator validates types and required fields
expected: `Schema.Validator.validate/2` checks types (string, integer, number, boolean, array, object), required fields, and nested object validation. Returns `{:ok, data}` or `{:error, errors}` with field-level details.
result: pass
evidence: ValidatorTest — 19 tests pass covering required keys (4), type checking (7), nested objects (2), combined errors (1), edge cases (2)

### 4. Schema.Validator handles enum constraints
expected: When the schema specifies `enum` values for a field, the validator rejects values not in the allowed set with a clear error message.
result: pass
evidence: ValidatorTest — "enum passes when value is in enum" + "enum fails when value is not in enum" both pass

### 5. Schema.Validator handles nullable fields
expected: When a schema property has nullable type declaration, the validator accepts `nil`/`null` values without error.
result: pass
evidence: ValidatorTest — "nil values pass type checks (nullable)" passes

### 6. OpenAI adapter injects response_format
expected: When `schema:` is passed, the OpenAI adapter injects `response_format` with `type: "json_schema"`. Without `schema:`, no `response_format` is added. Works alongside tools_json.
result: pass
evidence: OpenAIStructuredTest — 3 tests pass (injects response_format, does not inject without schema, includes tools alongside)

### 7. OpenRouter adapter injects response_format
expected: The OpenRouter adapter injects `response_format` with the schema when provided, and omits it otherwise.
result: pass
evidence: OpenRouterStructuredTest — 2 tests pass (injects response_format, does not inject without schema)

### 8. Anthropic adapter uses synthetic tool injection
expected: When `schema:` is passed, the Anthropic adapter injects a synthetic tool definition with the schema as input_schema. On response, it extracts structured data from the tool_use content block.
result: pass
evidence: AnthropicStructuredTest — 7 tests pass (inject with/without existing tools, tool_choice any/auto, extract tool_use input, mixed blocks, no interference with real tool_use)

### 9. AI.chat/2 validates and populates Response.parsed
expected: After provider returns, `AI.chat/2` decodes JSON, validates against schema via `Schema.validate_response/3`, and populates `Response.parsed`. On failure, returns `{:error, %{errors: [...]}}`.
result: pass
evidence: AIStructuredTest — 6 tests pass (resolve+validate+parsed, invalid_json error, validation_failed error, behaviour module, tools+schema path, no-schema passthrough)

### 10. Agent GenServer supports schema option
expected: Starting an Agent with `schema:` option causes structured output validation. The agent's response includes validated `parsed` data.
result: pass
evidence: AgentStructuredTest — 5 tests pass (validates+populates parsed, validation_failed for bad shape, invalid_json for non-JSON, behaviour module, no-schema nil)

### 11. Response struct includes parsed field
expected: `%PhoenixAI.Response{}` has a `parsed` field defaulting to `nil`. When structured output is used, this field contains the validated map.
result: pass
evidence: ResponseTest — "includes parsed field defaulting to nil" + "parsed can hold a map" both pass

## Summary

total: 11
passed: 11
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps

[none]
