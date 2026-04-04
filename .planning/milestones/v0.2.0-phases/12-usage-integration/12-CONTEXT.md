# Phase 12: Usage Integration - Context

**Gathered:** 2026-04-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Wire `Usage.t()` into `Response`, `StreamChunk`, and all 3 provider adapters. Every response from the library carries a normalized `%Usage{}` struct instead of a raw map. This is the integration phase — the struct and factory already exist from Phase 11.

</domain>

<decisions>
## Implementation Decisions

### Carrying Forward from Phase 11
- **D-01 (Phase 11):** `from_provider/2` uses explicit atom dispatch (:openai, :anthropic, :openrouter)
- **D-02 (Phase 11):** Nil/empty → zero-valued `%Usage{}` struct
- **D-06 (Phase 11):** `provider_specific` preserves raw map

### Stream Accumulator Logic
- **D-07:** Replace `chunk.usage || acc.usage` in `stream.ex:164` with explicit logic — pattern match or nil check instead of relying on `||` truthiness. A zero-valued `%Usage{}` is truthy and would incorrectly override a previous valid usage.
- **D-08:** In `build_response` (`stream.ex:187`), replace `acc.usage || %{}` with `acc.usage || %Usage{}` to return a zero-valued struct instead of a raw map when no usage was received.

### Telemetry Metadata
- **D-09:** Pass `%Usage{}` struct directly to telemetry metadata in `ai.ex:112`. Remove the `|| %{}` fallback — `Response.usage` is always a `%Usage{}` struct, never nil. Telemetry consumers access `.input_tokens`, `.output_tokens` etc. directly.

### Test Migration
- **D-10:** Update existing test assertions inline — change `response.usage["prompt_tokens"]` to `response.usage.input_tokens` etc. No helper abstractions. ~13 assertions across 6 test files need updating.

### Claude's Discretion
- Order of file modifications within each task
- Whether to update `provider_contract_test.exs` assertion (`is_map` still passes for structs)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 11 Output (Usage struct)
- `lib/phoenix_ai/usage.ex` — The `Usage` struct and `from_provider/2` factory (already implemented)
- `.planning/phases/11-usage-struct/11-CONTEXT.md` — Phase 11 decisions that constrain this phase

### Usage Normalization Spec
- `phoenix-ai-usage-normalization.md` (project root) — Provider mapping table and integration requirements

### Files to Modify
- `lib/phoenix_ai/response.ex` — Change `usage: map()` → `usage: Usage.t()`, default `%Usage{}`
- `lib/phoenix_ai/stream_chunk.ex` — Change `usage: map() | nil` → `usage: Usage.t() | nil`
- `lib/phoenix_ai/providers/openai.ex:57-64` — Call `Usage.from_provider(:openai, raw)` in `parse_response/1`
- `lib/phoenix_ai/providers/anthropic.ex:156,198` — Call `Usage.from_provider(:anthropic, raw)` in `parse_chunk/1` and `parse_response/1`
- `lib/phoenix_ai/providers/openrouter.ex:34-41` — Call `Usage.from_provider(:openrouter, raw)` in `parse_response/1`
- `lib/phoenix_ai/stream.ex:164,187` — Update accumulator logic and `build_response/1`
- `lib/ai.ex:112` — Simplify telemetry metadata (remove `|| %{}`)
- `lib/phoenix_ai/providers/test_provider.ex:109` — Verify it passes through `response.usage` correctly

### Test Files to Update
- `test/phoenix_ai/providers/openai_test.exs:22-23`
- `test/phoenix_ai/providers/anthropic_test.exs:22-23`
- `test/phoenix_ai/providers/openrouter_test.exs:22-23`
- `test/phoenix_ai/stream_test.exs:116,233`
- `test/phoenix_ai/stream_tools_test.exs:182`
- `test/phoenix_ai/response_test.exs:36`
- `test/phoenix_ai/providers/provider_contract_test.exs:43` (may not need change — `is_map` passes for structs)

</canonical_refs>

<code_context>
## Existing Code Insights

### Integration Points (with line references)
- `response.ex:8` — `usage: map()` type, `response.ex:20` — default `usage: %{}`
- `stream_chunk.ex:8` — `usage: map() | nil` type, `stream_chunk.ex:11` — default in defstruct
- `openai.ex:57` — `usage = Map.get(body, "usage", %{})` then `usage: usage` in Response
- `anthropic.ex:156` — `usage: Map.get(json, "usage")` in parse_chunk (streaming)
- `anthropic.ex:198` — `usage = Map.get(body, "usage", %{})` in parse_response
- `openrouter.ex:34` — `usage = Map.get(body, "usage", %{})` in parse_response
- `stream.ex:42` — accumulator starts with `usage: nil`
- `stream.ex:164` — `new_usage = chunk.usage || acc.usage` — the `||` works because chunk.usage is nil for intermediary chunks and a struct for the final chunk
- `stream.ex:187` — `usage: acc.usage || %{}` — needs to change to `|| %Usage{}`
- `ai.ex:112` — `%{status: :ok, usage: usage || %{}}` — simplify to `%{status: :ok, usage: usage}`
- `test_provider.ex:109` — `usage: response.usage` — passes through, works automatically

### Streaming Parsing per Provider
- **OpenAI** (`openai.ex:145`): `usage: Map.get(json, "usage")` in `parse_chunk/1` — needs `Usage.from_provider(:openai, ...)`
- **Anthropic** (`anthropic.ex:156`): `usage: Map.get(json, "usage")` in `parse_chunk/1` — needs `Usage.from_provider(:anthropic, ...)`
- **OpenRouter**: Uses OpenAI's `parse_chunk/1` indirectly via `stream.ex` dispatch — if openrouter has its own parse_chunk, needs updating too

### Established Patterns
- Provider adapters alias `{Response, StreamChunk}` — add `Usage` to the alias list
- Each adapter's `parse_response/1` builds `%Response{}` directly — insert `Usage.from_provider/2` call where raw usage is extracted

</code_context>

<specifics>
## Specific Ideas

No specific requirements — follow the normalization spec and existing patterns.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 12-usage-integration*
*Context gathered: 2026-04-03*
