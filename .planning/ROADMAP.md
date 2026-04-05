# Roadmap: PhoenixAI

## Milestones

- ✅ **v0.1.0 Initial Release** — Phases 1-10 (shipped 2026-03-31)
- ✅ **v0.2.0 Usage Normalization** — Phases 11-12 (shipped 2026-04-04)
- ✅ **v0.3.0 Guardrails** — Phases 13-17 (shipped 2026-04-05)
- 🔵 **v0.3.1 Provider Field** — Phase 18 (active)

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

<details>
<summary>✅ v0.3.0 Guardrails (Phases 13-17) — SHIPPED 2026-04-05</summary>

- [x] Phase 13: Core Contracts — `Policy` behaviour, `Request` struct, `PolicyViolation` struct
- [x] Phase 14: Pipeline Executor — `Guardrails.Pipeline.run/2` with halt-on-first-violation
- [x] Phase 15: Jailbreak System — `JailbreakDetector` behaviour, default keyword detector, `JailbreakDetection` policy
- [x] Phase 16: Content and Tool Policies — `ContentFilter` with pre/post hooks, `ToolPolicy` with allowlist/denylist
- [x] Phase 17: Presets, Telemetry, and Config — `Pipeline.preset/1`, telemetry events, `from_config/1` with NimbleOptions

</details>

### 🔵 v0.3.1 Provider Field (Active)

**Milestone Goal:** Add `:provider` field to `Response` struct so downstream consumers can identify the originating provider without extra configuration.

- [ ] **Phase 18: Provider Field** — Add `:provider` to `Response` struct, populate in all adapters, test coverage per provider, bump version to 0.3.1

## Phase Details

### Phase 18: Provider Field
**Goal**: Response struct carries the originating provider atom so callers can identify the source without inspecting raw provider data
**Depends on**: Phase 17
**Requirements**: RESP-01, RESP-02, RESP-03, RESP-04, RESP-05, TEST-01, REL-01
**Success Criteria** (what must be TRUE):
  1. `%PhoenixAI.Response{}` has a `:provider` field typed `atom() | nil`
  2. Calling any provider adapter returns a response where `response.provider` matches the expected atom (`:openai`, `:anthropic`, `:openrouter`, `:test`)
  3. All existing tests continue to pass — no breaking changes to the `Response` struct API
  4. `mix.exs` version is `"0.3.1"` and the library compiles clean
**Plans**: TBD

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Core Foundation | v0.1.0 | — | Complete | 2026-03-31 |
| 2. Remaining Providers | v0.1.0 | — | Complete | 2026-03-31 |
| 3. Tool Calling | v0.1.0 | — | Complete | 2026-03-31 |
| 4. Agent GenServer | v0.1.0 | — | Complete | 2026-03-31 |
| 5. Structured Output | v0.1.0 | — | Complete | 2026-03-31 |
| 6. Streaming Transport | v0.1.0 | — | Complete | 2026-03-31 |
| 7. Streaming + Tools | v0.1.0 | — | Complete | 2026-03-31 |
| 8. Pipeline Orchestration | v0.1.0 | — | Complete | 2026-03-31 |
| 9. Team Orchestration | v0.1.0 | — | Complete | 2026-03-31 |
| 10. Developer Experience | v0.1.0 | — | Complete | 2026-03-31 |
| 11. Usage Struct | v0.2.0 | — | Complete | 2026-04-04 |
| 12. Usage Integration | v0.2.0 | — | Complete | 2026-04-04 |
| 13. Core Contracts | v0.3.0 | — | Complete | 2026-04-05 |
| 14. Pipeline Executor | v0.3.0 | — | Complete | 2026-04-05 |
| 15. Jailbreak System | v0.3.0 | — | Complete | 2026-04-05 |
| 16. Content and Tool Policies | v0.3.0 | — | Complete | 2026-04-05 |
| 17. Presets, Telemetry, and Config | v0.3.0 | — | Complete | 2026-04-05 |
| 18. Provider Field | v0.3.1 | 0/1 | Not started | - |
