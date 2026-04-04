# Phase 11: Usage Struct - Context

**Gathered:** 2026-04-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Create the `PhoenixAI.Usage` struct with normalized fields and a `from_provider/2` factory function that maps raw provider usage maps into a consistent shape. This phase does NOT wire the struct into `Response` or `StreamChunk` — that is Phase 12.

</domain>

<decisions>
## Implementation Decisions

### Provider Dispatch Strategy
- **D-01:** `from_provider/2` uses explicit atom dispatch — `Usage.from_provider(:openai, raw_map)`. Each adapter passes its own provider atom. This is consistent with the existing `Error` struct pattern in the codebase.

### Nil/Empty Usage Handling
- **D-02:** When a provider returns no usage data (nil or empty map), `from_provider/2` returns a zero-valued `%Usage{}` struct (all token counts at 0, `provider_specific: %{}`). Consumers can always safely access `.usage` fields without nil checks.

### API Surface
- **D-03:** `from_provider/2` is a public API with `@doc` — consumers creating custom providers need to normalize usage through the same function. Name is `from_provider/2`, not `parse/2` or `new/2`.

### Field Semantics
- **D-04:** `cache_read_tokens` and `cache_creation_tokens` are `nil` when the provider does not support caching (e.g., OpenAI), and `non_neg_integer()` when supported (e.g., Anthropic). This distinguishes "not applicable" from "zero cached tokens".
- **D-05:** `total_tokens` is auto-calculated as `input_tokens + output_tokens` when the provider does not return it (e.g., Anthropic). When provider returns it explicitly, use the provider's value.
- **D-06:** `provider_specific` always holds the original raw usage map exactly as received from the provider, preserving backward compatibility.

### Claude's Discretion
- Internal module organization (single file vs multiple)
- Test structure and helper placement
- Guard clauses vs pattern matching for validation

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Usage Normalization Spec
- `phoenix-ai-usage-normalization.md` (project root) — Defines the struct fields, provider mapping table, and integration points

### Existing Structs (patterns to follow)
- `lib/phoenix_ai/response.ex` — Current `usage: map()` field that will change in Phase 12
- `lib/phoenix_ai/stream_chunk.ex` — Current `usage: map() | nil` field that will change in Phase 12
- `lib/phoenix_ai/error.ex` — Uses provider atom pattern (`:openai`, `:anthropic`, `:openrouter`)

### Provider Adapters (understand raw usage shapes)
- `lib/phoenix_ai/providers/openai.ex` — `Map.get(body, "usage", %{})` at line 57
- `lib/phoenix_ai/providers/anthropic.ex` — `Map.get(json, "usage")` at line 156, `Map.get(body, "usage", %{})` at line 198
- `lib/phoenix_ai/providers/openrouter.ex` — `Map.get(body, "usage", %{})` at line 34

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `PhoenixAI.Error` struct: Provider atom pattern (`:openai`, `:anthropic`, `:openrouter`) — reuse same atoms for `from_provider/2`
- `PhoenixAI.ToolCall`, `PhoenixAI.ToolResult` structs: Follow same `@type t` + `defstruct` pattern

### Established Patterns
- All data structs use `@type t :: %__MODULE__{}` typespec + `defstruct` in the same module
- Provider adapters do `Map.get(body, "usage", %{})` — raw JSON map with string keys
- No validation on struct fields — structs are simple data containers

### Integration Points
- Phase 12 will modify `Response.usage` and `StreamChunk.usage` types
- Phase 12 will modify each provider adapter's `parse_response/1` to call `Usage.from_provider/2`
- `lib/phoenix_ai/stream.ex` line 164: `new_usage = chunk.usage || acc.usage` — must work with `Usage.t()` in Phase 12
- `lib/ai.ex` line 111-112: telemetry metadata accesses `response.usage` — must work with `Usage.t()` in Phase 12

</code_context>

<specifics>
## Specific Ideas

- Provider mapping table is fully defined in the normalization spec document — follow it exactly
- The normalization doc suggests `0` as default for token fields in the struct definition, but per D-04, cache fields default to `nil`

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 11-usage-struct*
*Context gathered: 2026-04-03*
