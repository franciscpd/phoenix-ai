# Roadmap: PhoenixAI

## Milestones

- ✅ **v0.1.0 Initial Release** — Phases 1-10 (shipped 2026-03-31)
- 🚧 **v0.2.0 Usage Normalization** — Phases 11-12 (in progress)

## Phases

<details>
<summary>✅ v0.1.0 Initial Release (Phases 1-10) — SHIPPED 2026-03-31</summary>

- [x] Phase 1: Core Foundation — Data model, Provider behaviour, OpenAI adapter
- [x] Phase 2: Remaining Providers — Anthropic, OpenRouter, unified dispatch
- [x] Phase 3: Tool Calling — Tool behaviour, per-provider injection, tool loop
- [x] Phase 4: Agent GenServer — Completion loop, DynamicSupervisor
- [x] Phase 5: Structured Output — JSON schema, validation
- [x] Phase 6: Streaming Transport — Finch SSE, buffer parser
- [x] Phase 7: Streaming + Tools — Combined scenario, callback/PID delivery
- [x] Phase 8: Pipeline Orchestration — Sequential railway
- [x] Phase 9: Team Orchestration — Parallel Task.async_stream
- [x] Phase 10: Developer Experience — TestProvider, telemetry, NimbleOptions, docs

</details>

### 🚧 v0.2.0 Usage Normalization (In Progress)

**Milestone Goal:** Normalize token usage data across all providers into a unified `PhoenixAI.Usage` struct, eliminating per-consumer normalization burden.

- [ ] **Phase 11: Usage Struct** — Define `PhoenixAI.Usage` struct, `from_provider/2` factory, auto-calculated totals, and `provider_specific` backward-compat field
- [ ] **Phase 12: Usage Integration** — Wire `Usage.t()` into `Response`, `StreamChunk`, and all provider adapters

## Phase Details

### Phase 11: Usage Struct
**Goal**: The `PhoenixAI.Usage` struct exists with a working factory that normalizes any provider's raw usage map into a consistent shape
**Depends on**: Phase 10 (v0.1.0 complete)
**Requirements**: USAGE-01, USAGE-02, USAGE-03, COMPAT-01
**Success Criteria** (what must be TRUE):
  1. `PhoenixAI.Usage` is a struct with fields: `input_tokens`, `output_tokens`, `total_tokens`, `cache_read_tokens`, `cache_creation_tokens`, `provider_specific`
  2. `Usage.from_provider(:openai, raw_map)` returns a populated `%Usage{}` struct
  3. `Usage.from_provider(:anthropic, raw_map)` returns a populated `%Usage{}` struct
  4. When a provider does not return `total_tokens`, the struct auto-calculates it as `input_tokens + output_tokens`
  5. `provider_specific` field holds the original raw usage map exactly as received from the provider
**Plans**: TBD

### Phase 12: Usage Integration
**Goal**: Every `Response` and `StreamChunk` produced by the library carries a `Usage.t()` instead of a raw map, with all three provider adapters calling `Usage.from_provider/2` at parse time
**Depends on**: Phase 11
**Requirements**: INTG-01, INTG-02, INTG-03
**Success Criteria** (what must be TRUE):
  1. `Response.usage` is typed as `Usage.t()` and populated on every successful non-streaming call across all providers
  2. `StreamChunk.usage` is typed as `Usage.t() | nil` and populated on the final chunk of a streaming response
  3. OpenAI, Anthropic, and OpenRouter adapters each call `Usage.from_provider/2` during response parsing — no raw usage maps escape adapter boundaries
**Plans**: TBD

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Core Foundation | v0.1.0 | - | Complete | 2026-03-29 |
| 2. Remaining Providers | v0.1.0 | - | Complete | 2026-03-29 |
| 3. Tool Calling | v0.1.0 | - | Complete | 2026-03-30 |
| 4. Agent GenServer | v0.1.0 | - | Complete | 2026-03-30 |
| 5. Structured Output | v0.1.0 | - | Complete | 2026-03-30 |
| 6. Streaming Transport | v0.1.0 | - | Complete | 2026-03-30 |
| 7. Streaming + Tools | v0.1.0 | - | Complete | 2026-03-30 |
| 8. Pipeline Orchestration | v0.1.0 | - | Complete | 2026-03-31 |
| 9. Team Orchestration | v0.1.0 | - | Complete | 2026-03-31 |
| 10. Developer Experience | v0.1.0 | - | Complete | 2026-03-31 |
| 11. Usage Struct | v0.2.0 | 0/? | Not started | - |
| 12. Usage Integration | v0.2.0 | 0/? | Not started | - |
