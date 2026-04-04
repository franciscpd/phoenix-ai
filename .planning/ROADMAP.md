# Roadmap: PhoenixAI

## Milestones

- ✅ **v0.1.0 Initial Release** — Phases 1-10 (shipped 2026-03-31)
- ✅ **v0.2.0 Usage Normalization** — Phases 11-12 (shipped 2026-04-04)

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

<details>
<summary>✅ v0.2.0 Usage Normalization (Phases 11-12) — SHIPPED 2026-04-04</summary>

- [x] Phase 11: Usage Struct — `PhoenixAI.Usage` struct, `from_provider/2` factory, auto-calculated totals, `provider_specific` backward-compat field
- [x] Phase 12: Usage Integration — Wire `Usage.t()` into `Response`, `StreamChunk`, and all provider adapters

</details>

## Progress

| Phase | Milestone | Status | Completed |
|-------|-----------|--------|-----------|
| 1. Core Foundation | v0.1.0 | Complete | 2026-03-29 |
| 2. Remaining Providers | v0.1.0 | Complete | 2026-03-29 |
| 3. Tool Calling | v0.1.0 | Complete | 2026-03-30 |
| 4. Agent GenServer | v0.1.0 | Complete | 2026-03-30 |
| 5. Structured Output | v0.1.0 | Complete | 2026-03-30 |
| 6. Streaming Transport | v0.1.0 | Complete | 2026-03-30 |
| 7. Streaming + Tools | v0.1.0 | Complete | 2026-03-30 |
| 8. Pipeline Orchestration | v0.1.0 | Complete | 2026-03-31 |
| 9. Team Orchestration | v0.1.0 | Complete | 2026-03-31 |
| 10. Developer Experience | v0.1.0 | Complete | 2026-03-31 |
| 11. Usage Struct | v0.2.0 | Complete | 2026-04-03 |
| 12. Usage Integration | v0.2.0 | Complete | 2026-04-04 |
