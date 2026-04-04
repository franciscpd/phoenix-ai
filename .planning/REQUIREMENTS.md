# Requirements: PhoenixAI v0.3.0 Guardrails

**Defined:** 2026-04-04
**Core Value:** Developers can build AI-powered agents with skills, sequential pipelines, and parallel execution using idiomatic Elixir/Phoenix patterns and BEAM concurrency primitives.

## v0.3.0 Requirements

Requirements for the guardrails milestone. Each maps to roadmap phases.

### Core Framework

- [ ] **CORE-01**: Developer can define custom policies by implementing the `Policy` behaviour with `check/2` callback
- [ ] **CORE-02**: `Request` struct carries messages, user_id, conversation_id, tool_calls, metadata, halted flag, and violation through the pipeline
- [ ] **CORE-03**: `PolicyViolation` struct provides structured error with policy module, reason, message, and metadata
- [ ] **CORE-04**: `Pipeline.run/2` executes policies sequentially, halting on first violation and returning `{:ok, request} | {:error, violation}`

### Jailbreak Detection

- [ ] **JAIL-01**: Developer can implement custom jailbreak detectors via the `JailbreakDetector` behaviour with `detect/2` callback
- [ ] **JAIL-02**: Default keyword detector scores messages against role override, instruction override, DAN patterns, and encoding evasion categories
- [ ] **JAIL-03**: `JailbreakDetection` policy accepts `:detector`, `:scope` (last_message/all_user_messages), and `:threshold` options

### Content & Tool Policies

- [ ] **FILT-01**: `ContentFilter` policy accepts `:pre` and `:post` function hooks that can modify messages or reject with error
- [ ] **TOOL-01**: `ToolPolicy` accepts `:allow` (allowlist) or `:deny` (denylist) options, rejects disallowed tools with structured violation
- [ ] **TOOL-02**: `ToolPolicy` raises at config time if both `:allow` and `:deny` are provided

### Presets & Integration

- [ ] **PRES-01**: `Pipeline.preset/1` resolves `:default`, `:strict`, and `:permissive` atoms to composable policy lists
- [ ] **TELE-01**: Telemetry events emitted for pipeline start/stop/exception, per-policy start/stop/exception, and jailbreak detected
- [ ] **CONF-01**: `guardrails:` keyword list accepted in NimbleOptions config with policies, preset, jailbreak_threshold, jailbreak_scope, and jailbreak_detector keys

## Future Requirements

Deferred to `phoenix_ai_store` or later milestones.

### Stateful Policies (phoenix_ai_store)

- **BUDGET-01**: TokenBudget policy reads token counts from stored messages
- **BUDGET-02**: CostBudget policy reads cost records from store
- **BUDGET-03**: Extended presets with stateful policies

### Output Guardrails

- **OUT-01**: Post-response output filtering pipeline
- **OUT-02**: Response content validation policies

## Out of Scope

| Feature | Reason |
|---------|--------|
| TokenBudget / CostBudget policies | Require persistent storage — belongs in `phoenix_ai_store` |
| ML-based jailbreak classifiers | External model dependency — consumers swap via JailbreakDetector behaviour |
| Output/response filtering pipeline | Adds executor complexity — ContentFilter `:post` hook covers basic cases |
| Rate limiting | Requires process state or external store — not a stateless concern |
| Automatic wiring into chat/2 or stream/2 | Breaking change — guardrails must be opt-in |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| CORE-01 | — | Pending |
| CORE-02 | — | Pending |
| CORE-03 | — | Pending |
| CORE-04 | — | Pending |
| JAIL-01 | — | Pending |
| JAIL-02 | — | Pending |
| JAIL-03 | — | Pending |
| FILT-01 | — | Pending |
| TOOL-01 | — | Pending |
| TOOL-02 | — | Pending |
| PRES-01 | — | Pending |
| TELE-01 | — | Pending |
| CONF-01 | — | Pending |

**Coverage:**
- v0.3.0 requirements: 13 total
- Mapped to phases: 0
- Unmapped: 13 ⚠️

---
*Requirements defined: 2026-04-04*
*Last updated: 2026-04-04 after initial definition*
