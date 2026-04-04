# Project Research Summary

**Project:** PhoenixAI v0.3.0 — Middleware-Chain Guardrails Policy System
**Domain:** Elixir AI Library — Pre-call Safety Policy Framework
**Researched:** 2026-04-04
**Confidence:** HIGH

## Executive Summary

PhoenixAI v0.3.0 adds a structured guardrails policy system to an already-shipped Elixir AI library (v0.2.0). The milestone is self-contained: it introduces a middleware-chain that runs as a synchronous pre-call gate between the consumer call site and the provider adapter layer. The system is implemented entirely with Elixir stdlib primitives — `Enum.reduce_while/3`, `@behaviour`, and `defstruct` — requiring zero new runtime dependencies. The Elixir guardrails ecosystem is nearly empty as of 2026, which means this implementation will be one of the first production-ready Elixir guardrails libraries and can set the standard for idiomatic design in this space.

The recommended approach is a two-level behaviour system: a `Policy` behaviour for composable policy modules, and a `JailbreakDetector` behaviour for pluggable detection algorithms. Three concrete policies ship by default — `JailbreakDetection`, `ContentFilter`, and `ToolPolicy` — assembled into named presets (`:default`, `:strict`, `:permissive`). The pipeline executor is `Enum.reduce_while/3` with halt-on-first-violation semantics, mirroring Plug's halt model without the `Plug.Conn` dependency. This design is explicitly Phoenix-independent and stateless: all stateful concerns (rate limiting, cost budgets) are deferred to the companion `phoenix_ai_store` library.

The primary risk is scope creep. ML-based jailbreak detection, post-call output rails, and PII masking are all natural requests that would bloat the core library and introduce mandatory heavy dependencies. The mitigation is the `JailbreakDetector` behaviour: it makes the default `KeywordDetector` swappable without changing any pipeline code, so consumers can plug in ML-based or API-backed detectors as separate modules. A second risk is the `Policy` behaviour contract becoming a bottleneck — the `assigns` map on `Request` provides the escape hatch for inter-policy communication without breaking the `check/2` signature.

---

## Key Findings

### Recommended Stack

No new runtime dependencies are required. The guardrails system is built entirely on Elixir stdlib plus two existing deps (`nimble_options ~> 1.1` for policy config validation, `telemetry ~> 1.3` for pipeline events). Two libraries were evaluated and explicitly rejected: `llm_guard` (alpha status, 434 all-time downloads — too early-stage) and `pluggable` (elegant API but unnecessary since `Enum.reduce_while/3` expresses halt semantics cleanly without adding a dependency). ML-based detection via `Nx`/`Bumblebee` is intentionally excluded from the core library — consumers opt into it by implementing the `JailbreakDetector` behaviour with their own module. The only mix.exs change needed is adding the new `Guardrails` module group to ExDoc `groups_for_modules` config.

**Core technologies:**
- `Enum.reduce_while/3` (stdlib): pipeline executor — zero-dep halt-on-first-violation semantics
- `@behaviour` + `@callback` (stdlib): policy and detector contracts — compile-time callback enforcement via `@impl true`
- `defstruct` (stdlib): `Request` and `PolicyViolation` — typed pipeline context carriers
- `NimbleOptions ~> 1.1` (existing dep): policy config validation — nested keyword_list schemas
- `telemetry ~> 1.3` (existing dep): pipeline instrumentation — pass/violation events

### Expected Features

**Must have (table stakes — v0.3.0 launch):**
- `%Guardrails.Request{}` struct — typed context flowing through the policy chain (messages, tools, provider, model, assigns)
- `%Guardrails.PolicyViolation{}` struct — structured halt reason enabling machine-readable error handling
- `Policy` behaviour with `check/2` — the only extension point for new policies
- `Pipeline.run/2` — ordered chain with halt-on-first-violation, emits telemetry
- `JailbreakDetector` behaviour — makes detection algorithm replaceable independently of the policy wrapper
- `Detectors.KeywordDetector` — default regex-based jailbreak heuristics using curated patterns
- `Policies.JailbreakDetection` — wraps detector with `scope` (`:user | :system | :all`) and `threshold` config
- `Policies.ContentFilter` — `pre_fn`/`post_fn` hooks for user-provided content inspection logic
- `Policies.ToolPolicy` — allowlist/denylist check against `request.tools`
- `Guardrails.Presets` — `:default`, `:strict`, `:permissive` resolvers returning `[{module, opts}]` lists

**Should have (v0.3.x patches):**
- `PhoenixAI.Agent` integration — `guardrails:` opt in `prompt/3`, gate before Task spawn
- Telemetry events — `[:phoenix_ai, :guardrails, :violation]` and `[:phoenix_ai, :guardrails, :pass]`
- `opts_schema/0` on each policy — NimbleOptions validation per policy at runtime

**Defer (v0.4+):**
- Output rails — post-call response inspection requires a second `check_output/2` callback, significantly complicating the executor
- `phoenix_ai_ml_guards` companion library — `JailbreakDetector` behaviour backed by Bumblebee text classification
- Custom preset builder macro — `use PhoenixAI.Guardrails.Preset, base: :strict`

**Anti-features (explicitly excluded by design):**
- Built-in ML classifier — would mandate Bumblebee/Nx as a hard dep; kills adoption for simple use cases
- Rate limiting policy — stateful; belongs in `phoenix_ai_store`
- PII detection/masking — regex-based PII has unacceptable false-positive rates; `ContentFilter` pre_fn hook is the correct primitive
- Automatic retry on violation — hides failures, can cause infinite loops; return `{:error, violation}` and let the caller decide
- Guardrails DSL — Elixir behaviours + keyword config is already the declarative DSL; no Colang-style language needed

### Architecture Approach

Guardrails runs as a synchronous, stateless gate in the caller's process — not in a GenServer. The pipeline is `Guardrails.Pipeline.run(request, policies)` returning `{:ok, request} | {:halt, %PolicyViolation{}}`. Integration happens in `PhoenixAI.Agent.handle_call/3` (via a `with` chain before Task spawn) and as a documented opt-in pattern for direct `chat/2` callers. Provider adapters are not modified — the gate runs upstream. The `assigns` map on `%Guardrails.Request{}` enables inter-policy annotation (e.g., `JailbreakDetection` sets `assigns.jailbreak_score` for downstream logging policies) without mutating the message list or changing the `check/2` signature.

**Major components:**
1. `Guardrails.Policy` (behaviour) — contract every policy module must implement; single `check/2` callback returning `{:ok, request} | {:halt, violation}`
2. `Guardrails.Request` (struct) — immutable pipeline context: messages, tools, provider, model, assigns map
3. `Guardrails.PolicyViolation` (struct) — structured halt reason: policy, reason, severity, metadata
4. `Guardrails.Pipeline` — `Enum.reduce_while` executor; emits telemetry on pass and halt; maps `{:halt, v}` to `{:error, v}` at boundary
5. `Guardrails.JailbreakDetector` (behaviour) — second-level contract separating "when to block" from "what counts as jailbreak"
6. `Detectors.KeywordDetector` — default impl; compiled regex patterns; pure Elixir; sub-millisecond
7. `Policies.JailbreakDetection` — wraps detector with scope/threshold config; delegates detection
8. `Policies.ContentFilter` — delegates to user-provided `pre_fn`/`post_fn` callbacks; no built-in classifier
9. `Policies.ToolPolicy` — set membership check against tool allowlist or denylist
10. `Guardrails.Presets` — plain functions returning `[{module, opts}]` lists; inspectable and overridable

**File structure:**
```
lib/phoenix_ai/guardrails/
  policy.ex, request.ex, policy_violation.ex, pipeline.ex, presets.ex
  jailbreak_detector.ex
  jailbreak_detector/default.ex
  policies/jailbreak_detection.ex, content_filter.ex, tool_policy.ex
```

### Critical Pitfalls

Note: PITFALLS.md covers the full library (v0.1–v0.2 concerns). The pitfalls most directly relevant to the guardrails milestone are:

1. **Putting guardrail logic in provider adapters** — adapters must stay clean (single responsibility: translate to HTTP). The gate must run upstream in the caller's path. Any policy check inside `OpenAI.chat/2` or `Anthropic.chat/2` violates the architecture and requires touching multiple adapter files for every new policy.

2. **Making the pipeline a GenServer** — would serialize all guardrail checks through a single process bottleneck. `Guardrails.Pipeline.run/2` must be a pure function; each call runs in the caller's process with no shared state.

3. **Returning `{:error, reason}` from policies instead of `{:halt, violation}`** — collides with provider error tuples at the call site. Callers cannot distinguish a policy block from a network error. The executor maps `{:halt, %PolicyViolation{}}` to `{:error, %PolicyViolation{}}` at the boundary; the struct type is the discriminator.

4. **Coupling `JailbreakDetection` and `JailbreakDetector.Default` into one module** — consumers cannot swap detection logic independently; testing the policy requires testing the detection algorithm simultaneously. The two-behaviour design separates these concerns and allows each to be tested in isolation with Mox.

5. **Using Protocol instead of Behaviour for the Policy contract** — protocols dispatch on data types; behaviours dispatch on modules. Policies are modules with function implementations. Behaviours give `@impl true` compile-time checks; protocols do not. This is consistent with the existing `PhoenixAI.Provider` behaviour pattern.

---

## Implications for Roadmap

Based on the dependency graph in FEATURES.md and the explicit build order in ARCHITECTURE.md, the natural phase structure has 5 phases. The ordering respects strict dependency direction: each phase produces compilable, tested modules that the next phase depends on.

### Phase 1: Core Contracts
**Rationale:** Nothing else compiles without these. `Request`, `PolicyViolation`, the `Policy` behaviour, and the `JailbreakDetector` behaviour are the shared types all downstream modules depend on. They have zero inter-dependencies and can be written in any order within this phase.
**Delivers:** Compilable behaviour contracts and structs; Mox mocks usable immediately for downstream testing
**Addresses:** Table-stakes features: Request struct, PolicyViolation struct, Policy `check/2` contract, JailbreakDetector `detect/2` contract
**Avoids:** Pitfall #3 (behaviour not protocol), Pitfall #4 (contract change after policies exist cascades across every module)

### Phase 2: Pipeline Executor
**Rationale:** The executor is the hardest-to-get-wrong component. Building it against stub (Mox) policies before any real policy exists forces the return types, telemetry events, and error mapping to be correct in isolation. Integration tests for the executor can be written with mocked policies before any concrete policy ships.
**Delivers:** `Guardrails.Pipeline.run/2` with halt-on-first-violation semantics; telemetry integration; integration test harness
**Uses:** `Enum.reduce_while/3`, `telemetry ~> 1.3`, Mox-mocked `Policy` behaviour
**Avoids:** Pitfall #2 (making the pipeline a GenServer — it must be a pure function from day one)

### Phase 3: Concrete Policies
**Rationale:** Each policy depends only on Phase 1 contracts and can be implemented independently. `JailbreakDetector.Default` must precede `JailbreakDetection` (detector before policy); `ContentFilter` and `ToolPolicy` have no inter-dependency. This is the heaviest implementation phase but each unit is independently testable.
**Delivers:** All three production-ready policies with unit tests; `JailbreakDetector.Default` with curated keyword/regex patterns borrowed from `llm_guard` reference
**Addresses:** Jailbreak detection (scope + threshold config), content filter (pre/post hooks), tool allowlist/denylist; entire MVP feature set minus presets
**Avoids:** Pitfall #4 (JailbreakDetection delegates to JailbreakDetector — keeps them independently testable and swappable); Pitfall #1 (no guardrail logic in provider adapters)

### Phase 4: Presets
**Rationale:** Presets are a thin layer that requires all three policies to be compilable. They are plain functions returning `[{module, opts}]` lists — zero implementation complexity, but cannot exist before their referenced modules compile. Completing this phase makes the guardrails system usable end-to-end from the consumer API.
**Delivers:** `:default`, `:strict`, `:permissive` preset resolvers; consumer-facing API is complete and usable standalone
**Addresses:** Composable presets feature; makes the guardrails system usable without manual policy assembly

### Phase 5: Agent Integration and Observability
**Rationale:** This is the only phase that touches existing production code (`PhoenixAI.Agent.handle_call/3`). Doing it last minimizes the window where existing tests could break. Telemetry events and NimbleOptions validation on policy opts also land here since they are additions to an already-stable pipeline.
**Delivers:** `guardrails:` opt in `Agent.prompt/3`; telemetry violation/pass events; `opts_schema/0` on each policy; complete documentation and ExDoc module group
**Implements:** Agent integration wiring; observability hooks; the complete v0.3.x feature set
**Avoids:** Pitfall #1 (Agent wires guardrails before Task spawn — provider adapter stays unchanged)

### Phase Ordering Rationale

- Contracts before implementations — a contract change after all policies exist would cascade across every policy module. Lock the contracts first.
- Executor before concrete policies — executor correctness is independently verifiable with Mox stubs. Building it first means the return type contract cannot drift between policy implementations.
- Presets after all policies — presets reference module atoms; compilation fails if any referenced module does not exist yet.
- Agent integration last — it modifies existing production code; late placement protects the existing test suite from instability during active development.

### Research Flags

Phases with standard patterns (skip `/gsd:research-phase`):
- **Phase 1 (Core Contracts):** Elixir `@behaviour` + `defstruct` patterns are thoroughly documented in architecture research. Implementation is straightforward.
- **Phase 2 (Pipeline Executor):** `Enum.reduce_while/3` pattern is documented and validated in STACK.md and ARCHITECTURE.md with working code examples. No ambiguity.
- **Phase 3 (Concrete Policies):** ContentFilter and ToolPolicy are simple set/callback operations. JailbreakDetector pattern list can be assembled from `llm_guard` GitHub reference as documented in STACK.md.
- **Phase 4 (Presets):** Plain functions returning keyword lists — no implementation complexity.

Phases that may benefit from targeted research during planning:
- **Phase 5 (Agent Integration):** The exact `handle_call/3` integration point is documented in ARCHITECTURE.md, but the interaction between new `guardrails:` opts and the existing Agent NimbleOptions schema (how to extend the schema without breaking existing call sites) may need a focused review of the current Agent implementation before writing the plan.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Zero new deps confirmed. Elixir stdlib patterns verified against official HexDocs. NimbleOptions nested schema verified against v1.1.1 docs. `llm_guard` and `pluggable` evaluated and rejected with clear rationale. |
| Features | HIGH | Cross-referenced NeMo Guardrails, OpenAI Agents SDK, LiteLLM, Guardrails AI. Table stakes and anti-features grounded in production framework comparison. Feature dependency graph fully specified. |
| Architecture | HIGH | Build order, exact integration points (`Agent.handle_call/3` clause shown), anti-patterns, component boundaries, and data flow diagrams all specified with code. Existing codebase patterns used as reference. |
| Pitfalls | HIGH | OTP/process pitfalls are battle-tested findings from official Elixir docs. Guardrails-specific pitfalls (contract design, behaviour vs protocol, executor purity) are well-grounded in Elixir idiom docs and codebase precedents. |

**Overall confidence:** HIGH

### Gaps to Address

- **Keyword pattern list for `KeywordDetector`:** STACK.md references `llm_guard`'s 34+ patterns as a source but does not enumerate them. During Phase 3 execution, the concrete pattern list must be assembled from the `llm_guard` GitHub source. This is a content gap, not an architecture gap — the code structure is fully specified.
- **Agent opts schema extension:** ARCHITECTURE.md describes the integration point conceptually with a code sketch. Before writing the Phase 5 plan, the current `PhoenixAI.Agent` NimbleOptions schema should be reviewed to confirm how `:guardrails` opts slot into existing validation without a breaking change.
- **Output guardrails design:** Explicitly deferred to v0.4.0 by design. The `ContentFilter` `post_fn` hook provides a consumer escape hatch for v0.3.0, but the library has no first-class post-call inspection mechanism. This is a known, intentional gap.

---

## Sources

### Primary (HIGH confidence)
- [NimbleOptions v1.1.1 HexDocs](https://hexdocs.pm/nimble_options/NimbleOptions.html) — nested keyword_list schema, validated opts
- [Enum.reduce_while HexDocs](https://hexdocs.pm/elixir/Enum.html#reduce_while/3) — pipeline halt semantics
- [Plug.Builder HexDocs](https://hexdocs.pm/plug/Plug.Builder.html) — halt pattern reference (not used directly)
- [Plug.Conn HexDocs](https://hexdocs.pm/plug/Plug.Conn.html) — assigns map, halt flag design reference
- [Elixir Behaviours — Elixir School](https://elixirschool.com/en/lessons/advanced/behaviours) — @callback contract pattern
- [Exq.Middleware.Pipeline HexDocs](https://hexdocs.pm/exq/Exq.Middleware.Pipeline.html) — assigns map in middleware context
- [NeMo Guardrails documentation](https://docs.nvidia.com/nemo/guardrails/latest/index.html) — production guardrails framework reference
- [OpenAI Agents SDK Guardrails](https://openai.github.io/openai-agents-python/guardrails/) — input guardrail halt pattern reference
- Existing `PhoenixAI.Pipeline.run/3` and `PhoenixAI.Agent.handle_call/3` (codebase) — direct integration point identification

### Secondary (MEDIUM confidence)
- [pluggable v1.1.0 — Hex.pm](https://hex.pm/packages/pluggable) — halt token pattern; evaluated and rejected
- [LiteLLM Custom Guardrail docs](https://docs.litellm.ai/docs/proxy/guardrails/custom_guardrail) — hook point comparison
- [Guardrails AI introduction](https://guardrailsai.com/docs) — validator chain comparison
- [LlmGuard GitHub (North-Shore-AI)](https://github.com/North-Shore-AI/LlmGuard) — Elixir guardrails reference; pattern lists source

### Tertiary (LOW confidence)
- [llm_guard v0.3.1 — Hex.pm](https://hex.pm/packages/llm_guard) — evaluated as reference only; alpha status, 434 downloads
- [AI Guardrails Production Implementation Guide 2026](https://iterathon.tech/blog/ai-guardrails-production-implementation-guide-2026) — blog, WebSearch only
- [Guardrails for AI Agents — Weights & Biases](https://wandb.ai/site/articles/guardrails-for-ai-agents/) — blog, WebSearch only

---
*Research completed: 2026-04-04*
*Ready for roadmap: yes*
