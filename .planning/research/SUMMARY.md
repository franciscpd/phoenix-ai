# Project Research Summary

**Project:** PhoenixAI — Elixir AI Integration Library
**Domain:** Multi-provider AI library with OTP-native agent orchestration
**Researched:** 2026-03-29
**Confidence:** HIGH

---

## Executive Summary

PhoenixAI is a library-grade Elixir project targeting the same problem space as `laravel/ai` but adapted to BEAM/OTP idioms. Research confirms a genuine, unmet ecosystem gap: no existing Elixir library combines multi-provider unified chat, tool calling, structured output, sequential pipelines, and OTP-native parallel agent execution in a single coherent package. The closest contender, `req_llm` (v1.9.0, 45+ providers), covers HTTP concerns well but lacks the agent behaviour, pipeline DSL, and GenServer-backed stateful sessions that PhoenixAI targets. `LangChain.ex` (v0.6.3) is framework-oriented and does not expose first-class OTP agent supervision — it actually delegates to `req_llm` itself for HTTP. This competitive gap validates building the full feature surface rather than wrapping an existing library.

The recommended approach is a layered architecture with strict component boundaries: HTTP transport (Req + Finch), provider adapter behaviour, core data model structs, agent runtime (GenServer), and a thin public API surface. The runtime dependency set should stay at six packages (`req`, `jason`, `ecto`, `nimble_options`, `server_sent_events`, `telemetry`) to avoid imposing a heavyweight transitive dependency tree on consumers. The build order must respect data flow: the canonical data model and provider behaviour contracts must exist before any adapter, agent, pipeline, or test infrastructure is written. Streaming must use Finch directly — not Req — because Req's plugin architecture does not support long-running SSE connections.

The biggest risks are architectural, not implementation-level. Leaky provider abstraction (normalizing what can't be normalized) causes rewrites when a second provider ships. Using Req for streaming causes silent buffering of full responses. Misusing GenServer as a shared streaming bottleneck collapses throughput under concurrent load. A custom OTP "framework layer" that wraps and hides primitives prevents consumers from integrating the library into their own supervision trees. All four pitfalls are preventable by design decisions made in the first two phases — they are not implementation bugs but architecture commitments.

---

## Key Findings

### Recommended Stack

The stack is lean and validated by cross-referencing the dependency graphs of `req_llm`, `anthropix`, `instructor`, and `LangChain.ex`. Every runtime dependency has a clear, non-overlapping purpose. The Elixir/OTP version floor is `~> 1.17` with `1.18+` recommended for the native `JSON` module; OTP 26+ is required for stable `proc_lib` improvements.

**Core technologies:**
- `req ~> 0.5` — HTTP client for non-streaming requests; industry standard in 2025-2026, used by all major AI libraries
- `jason ~> 1.4` — JSON encode/decode; de facto standard despite Elixir 1.18 stdlib `JSON` (ecosystem adoption of stdlib is still early for library use)
- `ecto ~> 3.12` — embedded schemas for request/response structs and structured output validation; works without a database
- `nimble_options ~> 1.1` — library configuration option validation with auto-generated docs; Dashbit-maintained standard
- `server_sent_events ~> 0.2` — SSE frame parsing; used as direct dep by `req_llm`; stateful buffer required (see Pitfall 2)
- `telemetry ~> 1.3` — instrumentation events; mandatory for any production Elixir library

**Important streaming caveat:** Use `Finch` directly for SSE streaming, not Req. This is a validated production decision from `req_llm` 1.0. Req works for standard request/response but does not support the long-running, stateful connections SSE requires.

**Do not depend on:** `jido`, `langchain`, `instructor`, `req_llm`, `openai_ex`, or `anthropix`. Study them as reference implementations only. PhoenixAI's value is the unified, OTP-native API — wrapping existing clients defeats the purpose and couples the library to their design decisions.

---

### Expected Features

Research confirms a two-wave feature structure that matches the dependency graph in FEATURES.md. The v1 features must ship together — a partial subset is not useful because agents require tool calling which requires the provider behaviour which requires the message format.

**Must have (table stakes — v1 must ship these together):**
- Multi-provider unified API (OpenAI, Anthropic, OpenRouter) — every equivalent library has this
- Synchronous text generation (`AI.chat/3`) — the "hello world" of the domain
- Streaming responses — users expect real-time token output; Phoenix Channels integration natural target
- Tool/skill calling with automatic loop — core of "agent" behaviour; all major frameworks expose this
- Structured output with validation — typed AI responses essential for pipelines
- `use PhoenixAI.Agent` behaviour — single declarative module with instructions, tools, schema
- Test sandbox / mock provider — critical ecosystem gap; no existing Elixir AI library has this
- Telemetry events — mandatory for any production library

**Should have (competitive differentiators — v1.x):**
- Sequential pipeline DSL (`PhoenixAI.Pipeline`) — prompt chaining; equivalent to laravel/ai `Pipeline::send()->through()`
- OTP-native parallel agent execution (`PhoenixAI.Team`) — genuine BEAM differentiator not available in any Elixir competitor
- Named agent GenServer + supervision — long-running stateful chatbot sessions
- Provider failover — try providers in order; matches laravel/ai failover feature
- Conversation history protocol (callbacks, no built-in persistence)

**Defer (v2+):**
- Image/audio/multimodal generation — insufficient core value relative to added provider complexity
- MCP client support — too early-stage
- Embeddings/RAG pipeline — separate companion library
- Built-in database persistence — anti-feature; kills non-Phoenix adoption

**Ecosystem gap confirmed:** No existing Elixir library combines the full laravel/ai feature surface (agents + tools + structured output + pipelines + parallelism) with OTP idioms. The market exists.

---

### Architecture Approach

The architecture is a 5-layer stack with strict dependency direction: HTTP transport at the bottom, provider adapters above it, core data model as the shared language, agent runtime as the orchestrator, and a thin public API surface at the top. Layers communicate only with adjacent layers — the agent runtime never touches HTTP; provider adapters never know about pipelines or agent state. This separation allows each component to be built, tested, and mocked in isolation.

**Major components:**
1. `PhoenixAI.Provider` (behaviour) — translate between canonical data model and each provider's HTTP API; one implementation per provider
2. Core data model (`Message`, `Conversation`, `ToolCall`, `ToolResult`, `Response`, `StreamChunk`) — the shared language; all adapters speak this; no layer bypasses these types
3. `PhoenixAI.Tool` (behaviour) — interface for callable functions; pure modules with no OTP; agent runtime dispatches to them
4. `PhoenixAI.Agent` (GenServer) — runs the completion-tool-call loop; owns one conversation's state; backed by DynamicSupervisor
5. `PhoenixAI.HTTP.Stream` (Finch direct) — per-request streaming transport; NOT a shared GenServer; one process per stream
6. `PhoenixAI.Pipeline` — sequential `{:ok, _}` / `{:error, _}` railway; pure `Enum.reduce_while`; no OTP needed
7. `PhoenixAI.Team` — parallel execution via `Task.async_stream` with `max_concurrency` control

**OTP process model:** The library exposes `child_spec/1` for optional components (Finch pool, DynamicSupervisor for agents). It never auto-starts processes in `Application.start/2`. Consumers integrate into their own supervision tree.

---

### Critical Pitfalls

Five pitfalls are architectural commitments that must be made in the first two phases. Getting any of these wrong triggers a rewrite.

1. **Leaky provider abstraction** — Do not flatten all provider differences into one struct. Model the shared core (messages, role, content) plus a `provider_options: map()` escape hatch. Test each provider independently against real fixture files. Warning sign: `if provider == :anthropic do` branches in shared code.

2. **SSE chunk fragmentation** — Never parse SSE line-by-line. One TCP packet can carry multiple events; one event can span two packets. Use a stateful buffer with `\n\n` boundary detection before JSON decoding. OpenAI SSE is not strictly spec-conformant. Warning sign: `Jason.decode!` crashes in streaming logs.

3. **GenServer as streaming bottleneck** — A single shared GenServer for streaming serializes all concurrent requests. Use `Task.Supervisor.async_nolink/3` for one isolated process per streaming session. Warning sign: a module named `StreamManager` that is a singleton GenServer.

4. **OTP framework layer that fights the platform** — Do not build a custom orchestration layer that wraps and hides OTP. Parallel agents are `Task.async_stream` calls. Supervision trees are the consumer's responsibility. Provide `child_spec/1`, not opaque wrappers. Warning sign: `PhoenixAI.Supervisor` auto-starting in the Application callback.

5. **Tool call result injection with wrong role** — OpenAI requires `role: "tool"` with `tool_call_id`; Anthropic requires `role: "user"` with `type: "tool_result"` content block. Injection must happen in the provider adapter, not in shared pipeline code. Test the full round-trip against both provider fixtures. Warning sign: tool working in single-provider tests, failing in multi-provider integration tests.

---

## Top 5 Most Impactful Findings

These are the cross-cutting findings with the highest influence on how the library is built.

**1. The streaming transport decision (Finch, not Req) must be made before writing a single line of streaming code.**
ARCHITECTURE and PITFALLS agree on this independently. Req does not support long-running SSE connections. ReqLLM 1.0 made this same production decision. If this is missed, the streaming implementation must be rewritten wholesale.

**2. The provider behaviour contract defines everything downstream.**
FEATURES, ARCHITECTURE, and PITFALLS all converge: the `@behaviour PhoenixAI.Provider` definition with `chat/2`, `stream/3`, `format_tools/1`, and `parse_response/1` is the single most important design decision. Every adapter, every agent, every test mock depends on this contract being right. It must be finalized in Phase 1 before any adapter is written.

**3. No existing Elixir library fills the complete feature surface — the gap is real.**
FEATURES confirmed via ecosystem gap analysis: `req_llm` has providers but no agent behaviour or pipelines; `LangChain.ex` has chains but no first-class OTP agent supervision; `Jido` has agents but no multi-provider support. PhoenixAI's scope is justified and differentiated.

**4. Tool call injection is the most likely silent bug in multi-provider support.**
PITFALLS identifies that OpenAI and Anthropic have structurally different tool result message formats. This will appear to work in OpenAI-only tests and fail silently with Anthropic. The fix (provider adapter handles injection) must be designed in, not retrofitted. Fixture tests for both providers are mandatory before shipping tool calling.

**5. The configuration API determines whether the library is testable and multi-tenant.**
PITFALLS is clear: `Application.get_env` as the primary config mechanism blocks test isolation and multi-tenant deployments. Call-site options must be the primary mechanism with env as fallback. This is a day-one API surface decision that cannot be changed without a breaking release.

---

## Open Questions

Questions that must be resolved before or during planning, because they affect phase structure and API surface.

1. **Structured output strategy: Ecto changesets or provider-native JSON schema?**
   ARCHITECTURE rates this MEDIUM confidence with a noted "needs design work." The options are: (a) Ecto embedded_schema as the primary interface (familiar to Phoenix devs, adds Ecto dependency for structured output specifically), or (b) plain map-based schema definition with optional Ecto integration. This choice affects the API signature of every agent that uses structured output. Recommend: resolve in Phase 3 planning with a dedicated spike.

2. **Agent conversation history API: who owns truncation?**
   PITFALLS (Pitfall 8) says never silently truncate but expose length/token estimates. FEATURES defers conversation history to v1.x. The open question is whether the Agent GenServer should enforce a `max_messages` guard or only expose metrics and let the consumer decide. This affects the Agent GenServer's state design and must be settled before the agent is built.

3. **Supervision tree API: `PhoenixAI.start_link/1` or pure `child_spec/1`?**
   PITFALLS is firm that auto-starting processes is wrong. But some consumers will want a one-line setup. The question is whether to provide a convenience `PhoenixAI.start_link/1` that starts the Finch pool and DynamicSupervisor, or require consumers to compose the child specs manually. The answer affects the library's `mix.exs` application configuration and the getting-started DX.

4. **Provider failover: synchronous retry or async circuit breaker?**
   FEATURES includes provider failover as a v1.x differentiator. PITFALLS does not address this directly. The question is whether failover means sequential retry (try OpenAI, if 429 try Anthropic) or true async circuit breaking with state. The simpler synchronous approach is sufficient for v1.x and avoids adding a stateful GenServer for circuit state.

5. **Phoenix streaming helpers: first-class or documentation pattern?**
   FEATURES lists Phoenix Channels/LiveView streaming helpers as a differentiator, but the library is designed to be Phoenix-independent. Shipping `PhoenixAI.LiveView` helpers would add a Phoenix dependency. The question is whether to include them in the core library or publish as a separate `phoenix_ai_live` companion package.

---

## Implications for Roadmap

The feature dependency graph from FEATURES.md, the build order from ARCHITECTURE.md, and the phase warnings from PITFALLS.md converge on a 6-phase build order.

### Phase 1: Core Foundation
**Rationale:** Every other component depends on the data model and provider behaviour contract. These must be stable before any adapter, agent, or test infrastructure is built. No shortcuts.
**Delivers:** The canonical data model structs, the provider behaviour definition, HTTP transport layer (Req + Finch), and a working OpenAI adapter with synchronous chat.
**Addresses:** "Multi-provider unified API" table stake, "Configurable providers" table stake, "Provider-agnostic message format" table stake.
**Avoids:** Pitfall 1 (leaky abstraction — design escape hatches in), Pitfall 10 (Behaviour not Protocol), Pitfall 7 (no auto-starting supervision), Pitfall 6 (call-site config, not only Application.get_env).
**Research flag:** Standard patterns — Behaviour-based adapter is well-documented in Elixir ecosystem.

### Phase 2: Agent Fundamentals (Tool Calling + Remaining Providers)
**Rationale:** Tool calling requires a working provider adapter (Phase 1) and the Tool behaviour. The agent loop can be built against a single provider (OpenAI) first, then Anthropic and OpenRouter are added — which also validates the abstraction holds across providers.
**Delivers:** Tool behaviour, Agent GenServer with completion-tool-call loop, Anthropic and OpenRouter provider adapters.
**Addresses:** "Tool/skill calling" table stake, "Agent behaviour" differentiator.
**Avoids:** Pitfall 5 (tool result injection — handled per-provider, not in shared code), Pitfall 3 (GenServer not used as streaming bottleneck here), Pitfall 4 (OTP primitives exposed directly).
**Research flag:** Needs research-phase on Anthropic tool result format differences and `tool_call_id` correlation requirements before writing the adapter.

### Phase 3: Structured Output
**Rationale:** Structured output requires a working chat flow (Phase 1). It must come before streaming to keep complexity isolated — streaming + structured output + tool calling is the hardest combination and should be deferred until each piece is independently stable.
**Delivers:** JSON schema generation from Ecto embedded schemas (or plain maps), provider-side structured output parameters, response validation and casting.
**Addresses:** "Structured output" table stake, "HasStructuredOutput" agent capability.
**Avoids:** Pitfall 1 (schema format varies by provider — handle in adapter, not shared code).
**Research flag:** Needs design decision spike on Ecto vs. plain map approach before writing implementation (see Open Questions #1).

### Phase 4: Streaming
**Rationale:** Streaming is independent of structured output but shares the provider adapter layer. Building it after Phases 1-3 means the adapter interfaces are stable and streaming is added as an additional code path.
**Delivers:** Finch SSE streaming in HTTP transport, `parse_chunk/1` callbacks in all three provider adapters, agent streaming mode, Phoenix helpers (or companion package decision).
**Addresses:** "Streaming responses" table stake.
**Avoids:** Pitfall 2 (stateful SSE buffer — not line-by-line), Pitfall 3 (Task-per-stream, not singleton GenServer), Pitfall 11 (streaming + tool calls tested together, not separately), Pitfall 13 (no blocking handle_call during streaming).
**Research flag:** Needs research-phase on streaming + tool call behavior for both OpenAI and Anthropic before writing the combined integration.

### Phase 5: Orchestration (Pipeline + Parallel Team)
**Rationale:** Pipeline and Team compose over stable agents (Phase 2). These are pure combinators — no new OTP primitives beyond what is already in place. Deferred here because they add no value until agents are working.
**Delivers:** `PhoenixAI.Pipeline` (sequential railway), `PhoenixAI.Team` (parallel `Task.async_stream`), DynamicSupervisor integration for named agent sessions.
**Addresses:** "Sequential pipeline DSL" differentiator, "OTP-native parallel agents" differentiator, "Named agent GenServer" differentiator.
**Avoids:** Pitfall 9 (expose `max_concurrency` with conservative default, add 429 backoff), Pitfall 14 (pass only what Tasks need, not full conversation structs), Pitfall 4 (use `Task.Supervisor` directly, not opaque wrapper).
**Research flag:** Standard patterns — `Task.async_stream` and `Enum.reduce_while` are well-documented Elixir.

### Phase 6: Developer Experience
**Rationale:** The library must be production-usable before these cross-cutting concerns are finalized. NimbleOptions schemas, the test sandbox, and telemetry events can be retrofitted without breaking the API — but leaving them to this phase avoids prematurely locking option schemas while interfaces are still evolving.
**Delivers:** NimbleOptions schemas for all public functions, `PhoenixAI.TestProvider` mock sandbox, telemetry events on all operations, provider failover, ExDoc documentation, Credo/Dialyzer clean baseline.
**Addresses:** "Test sandbox" differentiator, "Telemetry integration" differentiator, "Provider failover" differentiator.
**Avoids:** Pitfall 12 (use `~> major.minor` not patch-level version pins in published library).
**Research flag:** Standard patterns — telemetry and Mox are well-documented Elixir library standards.

### Phase Ordering Rationale

- Data model must exist before adapters (adapters output canonical structs).
- Provider behaviour must be defined before either adapters or agents (both depend on the contract).
- One provider working (OpenAI, Phase 1) is sufficient to build and test the agent loop (Phase 2).
- Anthropic and OpenRouter are added in Phase 2 — this is intentional because the tool result injection differences (Pitfall 5) must be validated early while the abstraction is still plastic.
- Structured output (Phase 3) precedes streaming (Phase 4) to isolate complexity — the combined streaming + structured output + tool calling scenario (Pitfall 11) is addressed in Phase 4 with explicit fixture tests.
- Orchestration (Phase 5) is last among core features because it composes over stable agents — it cannot be meaningfully built or tested before the agent loop is complete.
- Developer experience (Phase 6) is last because option schemas should be finalized only after the API surfaces have stabilized through implementation.

### Research Flags

Phases likely needing `research-phase` during planning:
- **Phase 2:** Anthropic tool result message format, `tool_call_id` correlation, and differences from OpenAI wire format. This is not well-documented outside official API references and community bug reports.
- **Phase 3:** Structured output design decision (Ecto vs. plain map) needs a documented spike before writing code. InstructorLite vs. custom Ecto approach trade-offs must be resolved.
- **Phase 4:** Streaming + tool call interaction for both OpenAI and Anthropic needs research before writing the combined integration. Known bugs (LiteLLM PR #12463) confirm this is non-trivial.

Phases with standard patterns (skip research-phase):
- **Phase 1:** Provider behaviour, Req HTTP client, canonical struct definitions — all well-documented Elixir patterns.
- **Phase 5:** `Task.async_stream`, `Enum.reduce_while` railway — standard idiomatic Elixir.
- **Phase 6:** Telemetry, Mox, NimbleOptions, ExDoc — all have comprehensive official documentation.

---

## Conflicts and Tensions

Areas where research files disagree or create tension that must be resolved during planning.

**Tension 1: Streaming transport — Req vs Finch**
STACK.md recommends `req` as the standard HTTP client and lists `finch` only as a transitive dependency. ARCHITECTURE.md and PITFALLS.md both explicitly say to use Finch directly for streaming. **Resolution:** Req is correct for non-streaming requests; Finch is required for SSE streaming. Both are needed. The `server_sent_events` library handles parsing. Document this as a deliberate two-path design.

**Tension 2: Ecto dependency scope**
STACK.md includes Ecto as a required runtime dependency for all consumers. FEATURES.md lists structured output as a feature (implying Ecto is appropriate). ARCHITECTURE.md rates the structured output approach as MEDIUM confidence with "needs design work." Ecto is a significant transitive dependency for a library that claims to be Phoenix-independent. **Resolution:** This is Open Question #1 — resolve during Phase 3 planning. The fallback is a plain-map-based schema definition with an optional Ecto integration behind a compile-time flag.

**Tension 3: Agent GenServer API — eagerness vs. composability**
FEATURES.md's MVP recommendation includes Named agent GenServer (v1.x). PITFALLS.md warns strongly against baking DynamicSupervisor into the library and hiding it from consumers. ARCHITECTURE.md provides `child_spec/1` as the correct pattern. **Resolution:** The Agent GenServer is built; the DynamicSupervisor is not started automatically. Provide `PhoenixAI.Agent.child_spec/1` and document how consumers start it in their own trees. This satisfies both the feature need and the OTP guidelines.

**Tension 4: Structured output and agent behaviour dependency**
FEATURES.md's dependency tree shows: Provider adapter → Chat → Structured output → Routing pattern. But ARCHITECTURE.md's build order defers structured output to Phase 3 (after agents in Phase 2). This means agents in Phase 2 cannot support structured output yet. **Resolution:** This is acceptable — Phase 2 agents use unstructured responses. Structured output is added to the agent behaviour in Phase 3. The Agent behaviour's `schema/0` callback is defined as an optional callback in Phase 2 (returning `nil` by default) and implemented in Phase 3.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All 6 runtime dependencies verified on hex.pm with download counts and active maintenance. Version compatibility cross-checked against LangChain.ex and req_llm dependency trees. The Finch-for-streaming decision is validated by two independent production sources. |
| Features | HIGH | Ecosystem gap analysis is thorough — all major Elixir AI libraries surveyed. Feature dependency graph is based on structural analysis of laravel/ai and Vercel AI SDK. MVP boundary is opinionated but well-justified. |
| Architecture | HIGH | All major architecture decisions validated by 2+ independent reference implementations. The one MEDIUM area (structured output integration pattern) is flagged as a gap. |
| Pitfalls | HIGH (OTP/process), MEDIUM (provider-specific) | OTP process pitfalls sourced from official Elixir docs and established community knowledge. Provider-specific format differences (tool results, streaming) sourced from community bug reports — accurate but may not be exhaustive for every provider. |

**Overall confidence:** HIGH

### Gaps to Address

- **Structured output API design:** Plain map vs. Ecto approach is unresolved. Address in Phase 3 planning with a dedicated spike comparing InstructorLite integration vs. custom implementation.
- **Phoenix streaming helpers scope:** Whether to include LiveView/Channel helpers in the core library or a companion package. Address before Phase 4 planning — affects whether Phoenix is a dev dependency.
- **Context window management strategy:** The truncation responsibility boundary (library enforces, or library informs and consumer decides) affects the Agent GenServer state design. Address in Phase 2 planning.
- **Provider-specific streaming edge cases:** Anthropic's "content before tool call in stream" pattern and OpenAI's index-based tool argument aggregation need fixture recordings. Collect before Phase 4 starts.

---

## Sources

### Primary (HIGH confidence)
- [req v0.5.17 — hex.pm](https://hex.pm/packages/req) — HTTP client verification
- [LangChain.ex v0.6.3 — hex.pm + hexdocs](https://hexdocs.pm/langchain/changelog.html) — competitive analysis, feature surface
- [req_llm v1.9.0 — hex.pm](https://hex.pm/packages/req_llm) — prior art architecture, Finch streaming decision
- [Elixir Library Guidelines — hexdocs.pm](https://hexdocs.pm/elixir/library-guidelines.html) — supervision, config, dependency guidelines
- [Process Anti-Patterns — Elixir v1.19.5](https://hexdocs.pm/elixir/process-anti-patterns.html) — GenServer pitfalls
- [Task.Supervisor — Elixir v1.19.5](https://hexdocs.pm/elixir/Task.Supervisor.html) — parallel execution patterns
- [NimbleOptions — hexdocs.pm](https://hexdocs.pm/nimble_options/NimbleOptions.html) — config validation
- [Mocks and explicit contracts — Dashbit Blog](https://dashbit.co/blog/mocks-and-explicit-contracts) — Mox/Behaviour pattern
- [ReqLLM 1.0 announcement](https://jido.run/blog/announcing-req_llm-1_0) — Finch-for-streaming production validation
- [Fly.io SSE streaming guide](https://fly.io/phoenix-files/streaming-openai-responses/) — SSE parsing patterns
- [Laravel AI SDK docs](https://laravel.com/docs/12.x/ai-sdk) — API surface reference

### Secondary (MEDIUM confidence)
- [instructor v0.1.0 — hex.pm](https://hex.pm/packages/instructor) — structured output pattern reference
- [anthropix v0.6.2 — hex.pm](https://hex.pm/packages/anthropix) — Anthropic streaming patterns
- [Alloy — Elixir Forum](https://elixirforum.com/t/alloy-a-minimal-otp-native-ai-agent-engine-for-elixir/74464) — minimal OTP agent loop validation
- [Jido — GitHub](https://github.com/agentjido/jido) — agent GenServer and multi-agent patterns
- [OpenAI SSE non-conformance thread](https://community.openai.com/t/assistants-streaming-not-conformant-with-sse-spec/760209) — streaming pitfall evidence
- [LiteLLM streaming + tools bug (PR #12463)](https://github.com/BerriAI/litellm/pull/12463) — streaming + tool call interaction pitfall
- [Elixir Forum: AI Agents in Elixir](https://elixirforum.com/t/is-anyone-working-on-ai-agents-in-elixir/69989) — ecosystem gap community signal

### Tertiary (LOW confidence)
- [openai_agents for Elixir — hexdocs](https://hexdocs.pm/openai_agents/) — v0.1.2, minimal documentation; noted as ecosystem signal only
- [Why Elixir/OTP doesn't need an Agent framework](https://goto-code.com/why-elixir-otp-doesnt-need-agent-framework-part-1/) — 404 at fetch time; referenced in multiple secondary sources; findings corroborated by official Elixir docs

---
*Research completed: 2026-03-29*
*Ready for roadmap: yes*
