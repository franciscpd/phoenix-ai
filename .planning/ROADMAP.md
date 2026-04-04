# Roadmap: PhoenixAI

## Milestones

- ✅ **v0.1.0 Initial Release** — Phases 1-10 (shipped 2026-03-31)
- ✅ **v0.2.0 Usage Normalization** — Phases 11-12 (shipped 2026-04-04)
- 🚧 **v0.3.0 Guardrails** — Phases 13-17 (in progress)

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

### 🚧 v0.3.0 Guardrails (In Progress)

**Milestone Goal:** Add a middleware-chain policy system for pre-call guardrails — enforcing jailbreak detection, content filtering, tool allowlists/denylists, and composable presets.

- [ ] **Phase 13: Core Contracts** — `Policy` behaviour, `Request` struct, `PolicyViolation` struct — the shared types everything else depends on
- [ ] **Phase 14: Pipeline Executor** — `Guardrails.Pipeline.run/2` with halt-on-first-violation semantics using `Enum.reduce_while/3`
- [ ] **Phase 15: Jailbreak System** — `JailbreakDetector` behaviour, `KeywordDetector` default impl, `JailbreakDetection` policy
- [ ] **Phase 16: Content and Tool Policies** — `ContentFilter` with pre/post hooks, `ToolPolicy` with allowlist/denylist modes
- [ ] **Phase 17: Presets, Telemetry, and Config** — `Pipeline.preset/1` resolvers, telemetry events, NimbleOptions guardrails config key

## Phase Details

### Phase 13: Core Contracts
**Goal**: Developers can reference stable, compilable `Policy` behaviour, `Request` struct, and `PolicyViolation` struct as the foundation for every downstream guardrail module
**Depends on**: Phase 12 (v0.2.0 complete)
**Requirements**: CORE-01, CORE-02, CORE-03
**Success Criteria** (what must be TRUE):
  1. A developer can implement the `Policy` behaviour by defining a module with a `check/2` callback — the compiler enforces the contract via `@impl true`
  2. A `%Guardrails.Request{}` can be constructed carrying `messages`, `user_id`, `conversation_id`, `tools`, `metadata`, `halted`, and `violation` fields
  3. A `%Guardrails.PolicyViolation{}` can be constructed with `policy`, `reason`, `message`, and `metadata` fields — providing machine-readable error discrimination
  4. Mox mocks for the `Policy` behaviour can be defined and used in tests for downstream pipeline and policy modules
**Plans**: TBD

### Phase 14: Pipeline Executor
**Goal**: Developers can run an ordered list of policies against a `Request` and receive `{:ok, request}` on pass or `{:error, %PolicyViolation{}}` on the first violation — with no shared process state
**Depends on**: Phase 13
**Requirements**: CORE-04
**Success Criteria** (what must be TRUE):
  1. `Guardrails.Pipeline.run(request, policies)` returns `{:ok, request}` when all policies pass
  2. `Guardrails.Pipeline.run(request, policies)` returns `{:error, %PolicyViolation{}}` and stops executing on the first policy that returns `{:halt, violation}`
  3. The pipeline is a pure function — it runs in the caller's process with no GenServer, no ETS, and no shared state
  4. Integration tests using Mox-stubbed policies validate all halt/pass paths without any concrete policy being implemented
**Plans**: TBD

### Phase 15: Jailbreak System
**Goal**: Developers can detect jailbreak attempts in user messages using a built-in keyword detector or by plugging in a custom detector — controlled by scope and threshold configuration
**Depends on**: Phase 14
**Requirements**: JAIL-01, JAIL-02, JAIL-03
**Success Criteria** (what must be TRUE):
  1. A developer can implement the `JailbreakDetector` behaviour with a `detect/2` callback and swap it into `JailbreakDetection` without changing the policy wrapper
  2. The default `KeywordDetector` assigns a score based on matches against role override, instruction override, DAN pattern, and encoding evasion categories — returning a float score for the given messages
  3. `JailbreakDetection` policy accepts `:detector`, `:scope` (`:last_message` or `:all_user_messages`), and `:threshold` options and halts the pipeline when the score exceeds the threshold
  4. `JailbreakDetection` passes when messages score below the threshold and returns `{:ok, request}` with no modification
**Plans**: TBD

### Phase 16: Content and Tool Policies
**Goal**: Developers can apply custom content inspection functions and tool allowlist/denylist rules as standalone policies in the guardrails pipeline
**Depends on**: Phase 15
**Requirements**: FILT-01, TOOL-01, TOOL-02
**Success Criteria** (what must be TRUE):
  1. `ContentFilter` policy accepts a `:pre` function hook that receives the request and can return `{:ok, request}` (optionally modifying messages) or `{:error, reason}` to halt the pipeline
  2. `ContentFilter` policy accepts a `:post` function hook with the same contract, applied after the `:pre` hook if both are provided
  3. `ToolPolicy` configured with `:allow` halts with a structured violation when a tool in `request.tools` is not in the allowlist
  4. `ToolPolicy` configured with `:deny` halts with a structured violation when a tool in `request.tools` is in the denylist
  5. `ToolPolicy` raises a compile-time-friendly error at configuration time if both `:allow` and `:deny` are provided together
**Plans**: TBD

### Phase 17: Presets, Telemetry, and Config
**Goal**: Developers can start the guardrails system with a named preset, observe pipeline execution through telemetry events, and configure guardrails via NimbleOptions without manually assembling policy lists
**Depends on**: Phase 16
**Requirements**: PRES-01, TELE-01, CONF-01
**Success Criteria** (what must be TRUE):
  1. `Pipeline.preset(:default)`, `Pipeline.preset(:strict)`, and `Pipeline.preset(:permissive)` each return a `[{module, opts}]` policy list that can be passed directly to `Pipeline.run/2`
  2. Telemetry events are emitted for pipeline start, pipeline stop, pipeline exception, per-policy start, per-policy stop, per-policy exception, and jailbreak detected — with metadata identifying the policy and outcome
  3. A `guardrails:` keyword list is accepted in the NimbleOptions config schema with `policies`, `preset`, `jailbreak_threshold`, `jailbreak_scope`, and `jailbreak_detector` keys — invalid values are rejected at validation time with a descriptive error
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
| 11. Usage Struct | v0.2.0 | - | Complete | 2026-04-03 |
| 12. Usage Integration | v0.2.0 | - | Complete | 2026-04-04 |
| 13. Core Contracts | v0.3.0 | 0/? | Not started | - |
| 14. Pipeline Executor | v0.3.0 | 0/? | Not started | - |
| 15. Jailbreak System | v0.3.0 | 0/? | Not started | - |
| 16. Content and Tool Policies | v0.3.0 | 0/? | Not started | - |
| 17. Presets, Telemetry, and Config | v0.3.0 | 0/? | Not started | - |
