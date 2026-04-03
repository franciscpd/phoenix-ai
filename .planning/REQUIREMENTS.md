# Requirements: PhoenixAI

**Defined:** 2026-04-03
**Core Value:** Developers can build AI-powered agents with skills, sequential pipelines, and parallel execution using idiomatic Elixir/Phoenix patterns and BEAM concurrency primitives.

## v0.2.0 Requirements

Requirements for usage normalization. Each maps to roadmap phases.

### Usage Struct

- [ ] **USAGE-01**: Library provides a `PhoenixAI.Usage` struct with normalized fields (input_tokens, output_tokens, total_tokens, cache_read_tokens, cache_creation_tokens, provider_specific)
- [ ] **USAGE-02**: Library provides `Usage.from_provider/2` that maps raw provider usage maps to the normalized struct
- [ ] **USAGE-03**: `total_tokens` is auto-calculated from `input_tokens + output_tokens` when the provider does not return it

### Integration

- [ ] **INTG-01**: `Response.usage` type is `Usage.t()` instead of `map()`
- [ ] **INTG-02**: `StreamChunk.usage` type is `Usage.t() | nil` instead of `map() | nil`
- [ ] **INTG-03**: Each provider adapter (OpenAI, Anthropic, OpenRouter) calls `Usage.from_provider/2` at response parse time

### Backward Compatibility

- [ ] **COMPAT-01**: `provider_specific` field preserves the original raw provider usage map

## Future Requirements

(None deferred for this milestone)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Cost calculation helpers | Consumer responsibility (e.g. phoenix_ai_store) |
| Token counting / estimation | Different concern, not part of usage normalization |
| Usage aggregation / analytics | Consumer-side feature, not runtime concern |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| USAGE-01 | — | Pending |
| USAGE-02 | — | Pending |
| USAGE-03 | — | Pending |
| INTG-01 | — | Pending |
| INTG-02 | — | Pending |
| INTG-03 | — | Pending |
| COMPAT-01 | — | Pending |

**Coverage:**
- v0.2.0 requirements: 7 total
- Mapped to phases: 0
- Unmapped: 7 ⚠️

---
*Requirements defined: 2026-04-03*
*Last updated: 2026-04-03 after initial definition*
