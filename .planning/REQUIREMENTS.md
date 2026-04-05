# Requirements: PhoenixAI

**Defined:** 2026-04-05
**Core Value:** Developers can build AI-powered agents with skills, sequential pipelines, and parallel execution using idiomatic Elixir/Phoenix patterns and BEAM concurrency primitives.

## v0.3.1 Requirements

Requirements for patch release. Each maps to roadmap phases.

### Response

- [ ] **RESP-01**: Response struct includes `:provider` field (`atom() | nil`)
- [ ] **RESP-02**: OpenAI adapter sets `provider: :openai` in `parse_response/1`
- [ ] **RESP-03**: Anthropic adapter sets `provider: :anthropic` in `parse_response/1`
- [ ] **RESP-04**: OpenRouter adapter sets `provider: :openrouter` in `parse_response/1`
- [ ] **RESP-05**: TestProvider adapter sets `provider: :test` in `parse_response/1`

### Testing

- [ ] **TEST-01**: Each provider test asserts `response.provider` matches expected atom

### Release

- [ ] **REL-01**: Version bumped to 0.3.1 in `mix.exs`

## Future Requirements

None for this patch release.

## Out of Scope

| Feature | Reason |
|---------|--------|
| Adding `:provider` to Usage struct | Separate concern — Usage normalization is provider-aware via `from_provider/2` already |
| Changing Provider behaviour signature | `parse_response/1` signature unchanged — backward compatible |
| Telemetry changes | Nice-to-have but not required for this release |
| Breaking changes | This is a non-breaking additive patch |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| RESP-01 | Phase 18 | Pending |
| RESP-02 | Phase 18 | Pending |
| RESP-03 | Phase 18 | Pending |
| RESP-04 | Phase 18 | Pending |
| RESP-05 | Phase 18 | Pending |
| TEST-01 | Phase 18 | Pending |
| REL-01 | Phase 18 | Pending |

**Coverage:**
- v0.3.1 requirements: 7 total
- Mapped to phases: 7
- Unmapped: 0 ✓

---
*Requirements defined: 2026-04-05*
*Last updated: 2026-04-05 after roadmap creation*
