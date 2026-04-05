# Phase 18: Provider Field - Context

**Gathered:** 2026-04-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Add `:provider` field to `%PhoenixAI.Response{}` struct. Populate it in each provider adapter's `parse_response/1`. Add telemetry metadata. Bump version to 0.3.1. StreamChunk and Usage are out of scope.

</domain>

<decisions>
## Implementation Decisions

### Response Struct
- **D-01:** Add `provider: atom() | nil` field to `%Response{}` defstruct and @type, defaulting to `nil` for backward compatibility

### Provider Adapters
- **D-02:** OpenAI adapter sets `provider: :openai` in `parse_response/1` (~line 60)
- **D-03:** Anthropic adapter sets `provider: :anthropic` in `parse_response/1` (~line 213)
- **D-04:** OpenRouter adapter sets `provider: :openrouter` in `parse_response/1` (~line 36)
- **D-05:** TestProvider `parse_response/1` changes from passthrough `body` to `%{body | provider: :test}` — consistent with other adapters setting provider in parse_response

### Telemetry
- **D-06:** Add `:provider` to telemetry event metadata for `[:phoenix_ai, :chat, :stop]` — enables cost tracking via telemetry handler without reading the response struct directly

### Testing
- **D-07:** Each provider test file asserts `response.provider == :expected_atom`

### Release
- **D-08:** Bump version to `"0.3.1"` in `mix.exs`

### Claude's Discretion
- Exact placement of `:provider` in defstruct field order
- Whether to add `:provider` to `[:phoenix_ai, :chat, :start]` telemetry as well (minor — provider is known at call time)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### PRD (source of truth)
- `../phoenix-ai-store/.planning/phases/06-cost-tracking/prd-phoenix-ai-provider-field.md` — Full PRD defining the change, all affected files, scope, and impact analysis

### Response struct
- `lib/phoenix_ai/response.ex` — Current Response struct definition (add :provider field here)

### Provider adapters (all parse_response/1 implementations)
- `lib/phoenix_ai/providers/openai.ex` ~line 60 — OpenAI parse_response builds %Response{}
- `lib/phoenix_ai/providers/anthropic.ex` ~line 213 — Anthropic parse_response builds %Response{}
- `lib/phoenix_ai/providers/openrouter.ex` ~line 36 — OpenRouter parse_response builds %Response{}
- `lib/phoenix_ai/providers/test_provider.ex` line 94 — TestProvider parse_response passthrough (needs change)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `%Response{}` struct at `lib/phoenix_ai/response.ex` — simple defstruct, adding a field is trivial
- Telemetry events already instrumented in the chat path — adding metadata key follows existing pattern

### Established Patterns
- All adapters construct `%Response{}` inside `parse_response/1` with the same field set — new field follows identical pattern
- v0.2.0 established the precedent: normalize provider information at the adapter boundary (Usage.from_provider/2)
- TestProvider is the exception: `parse_response/1` is a passthrough, so merge pattern (`%{body | provider: :test}`) is needed

### Integration Points
- `lib/phoenix_ai/chat.ex` or wherever telemetry events are emitted — add `:provider` to metadata
- Existing test files per provider — add assertion for `response.provider`

</code_context>

<specifics>
## Specific Ideas

- Follow the exact same pattern as v0.2.0 Usage normalization — set at the adapter boundary in parse_response/1
- PRD is the definitive spec — downstream agents should read it for the full change list

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 18-provider-field*
*Context gathered: 2026-04-05*
