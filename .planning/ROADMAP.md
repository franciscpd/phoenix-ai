# Roadmap: PhoenixAI

## Milestones

- ✅ **v0.1.0 Initial Release** — Phases 1-10 (shipped 2026-03-31)
- ✅ **v0.2.0 Usage Normalization** — Phases 11-12 (shipped 2026-04-04)
- ✅ **v0.3.0 Guardrails** — Phases 13-17 (shipped 2026-04-05)

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
