# Milestones

## v0.3.0 — Guardrails

**Shipped:** 2026-04-05
**Phases:** 5 | **Plans:** 5 | **Tests:** 421 (109 new)
**Timeline:** 1 day (Apr 4, 2026)
**Stats:** 1,005 LOC (guardrails lib), 680 LOC (guardrails tests), 49 commits

### Key Accomplishments

1. `Guardrails.Pipeline.run/2` policy middleware chain with halt-on-first-violation using `Enum.reduce_while/3`
2. `Policy` behaviour, `Request` struct, `PolicyViolation` struct — composable contracts for all guardrail policies
3. `JailbreakDetector` behaviour + default keyword detector with 4 scoring categories (role override, instruction override, DAN patterns, base64 evasion)
4. `JailbreakDetection` policy with configurable `:detector`, `:scope`, `:threshold` — swappable ML detectors via behaviour
5. `ContentFilter` policy with pre/post function hooks and `ToolPolicy` with allowlist/denylist enforcement
6. Named presets (`:default`, `:strict`, `:permissive`), `from_config/1` with NimbleOptions validation, and full telemetry instrumentation (pipeline span + per-policy events + jailbreak detection)

### Tech Debt

- `Request.halted` and `Request.violation` fields defined but unused by pipeline executor (future consumer use)
- `PhoenixAI.Conversation` stub module — dead code carried from v0.1.0

---

## v0.2.0 — Usage Normalization

**Shipped:** 2026-04-04
**Phases:** 2 | **Plans:** 2 | **Tests:** 326 (15 new)
**Timeline:** 1 day (Apr 3–4, 2026)
**Stats:** 2,776 LOC (lib), 4,752 LOC (test), 22 commits

### Key Accomplishments

1. `PhoenixAI.Usage` normalized struct with `from_provider/2` factory for OpenAI, Anthropic, OpenRouter + generic fallback
2. Auto-calculated `total_tokens` when provider omits it (Anthropic, unknown providers)
3. `Response.usage` and `StreamChunk.usage` carry `Usage.t()` instead of raw maps — no raw usage maps escape adapter boundaries
4. Backward compatibility via `provider_specific` field preserving original raw provider map
5. OpenRouter adapter gained its own `parse_chunk/1` (previously delegated to OpenAI) for correct provider atom dispatch
6. Stream accumulator uses explicit nil checks instead of `||` truthiness for Usage struct compatibility

### Tech Debt

- `PhoenixAI.Conversation` stub module — dead code, never integrated (carried from v0.1.0)

### Archive

- [Roadmap](milestones/v0.2.0-ROADMAP.md)
- [Requirements](milestones/v0.2.0-REQUIREMENTS.md)
- [Audit](milestones/v0.2.0-MILESTONE-AUDIT.md)

---

## v0.1.0 — Initial Release

**Shipped:** 2026-03-31
**Phases:** 10 | **Plans:** 10 | **Tests:** 311
**Timeline:** 3 days (Mar 29–31, 2026)
**Stats:** 2,647 LOC (lib), 4,555 LOC (test), 141 commits

### Key Accomplishments

1. Multi-provider AI integration (OpenAI, Anthropic, OpenRouter) with unified dispatch API
2. Tool calling with per-provider wire format handling and automatic completion loop
3. Stateful Agent GenServer with conversation history and DynamicSupervisor support
4. Structured output with JSON schema validation (no Ecto dependency)
5. Real-time SSE streaming via Finch with combined streaming+tools support
6. Pipeline (sequential) and Team (parallel) orchestration primitives
7. Developer experience: TestProvider sandbox, telemetry spans, NimbleOptions validation, ExDoc guides
8. Published to Hex as `phoenix_ai ~> 0.1.0`

### Tech Debt

- `PhoenixAI.Conversation` stub module — dead code, never integrated

### Archive

- [Roadmap](milestones/v0.1.0-ROADMAP.md)
- [Requirements](milestones/v0.1.0-REQUIREMENTS.md)
- [Audit](milestones/v0.1.0-MILESTONE-AUDIT.md)
