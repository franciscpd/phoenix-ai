# Feature Research

**Domain:** AI Guardrails / Safety Policy Framework (Elixir library milestone)
**Researched:** 2026-04-04
**Confidence:** HIGH (cross-referenced NeMo Guardrails, OpenAI Agents SDK, LiteLLM, Guardrails AI, Plug middleware pattern)

---

## Context: What This Milestone Is

This research covers only the guardrails policy system being added as v0.3.0 to `phoenix_ai`. The library already ships multi-provider dispatch, tool calling, Agent GenServer, streaming, pipelines, and teams. This milestone adds a middleware-chain policy system that runs before (and optionally after) any AI call — enforcing jailbreak detection, content filtering, tool allowlists/denylists, and composable presets.

**Key constraint:** Stateless policies only. Stateful policies (TokenBudget, CostBudget) live in `phoenix_ai_store`.

---

## Feature Landscape

### Table Stakes (Users Expect These)

These are the non-negotiable features users expect from any AI guardrails system. Missing any of these makes the guardrails framework feel incomplete or unusable.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Policy behaviour with `check/2` | Every guardrails framework (NeMo, OpenAI SDK, LiteLLM, Guardrails AI) defines a first-class policy/validator interface. Developers expect a clear contract to implement custom policies. | LOW | `@callback check(request, opts) :: :ok \| {:halt, violation}` — mirrors Plug's `call/2` halt pattern. The `opts` are NimbleOptions-validated config per policy. |
| Halt-on-first-violation semantics | Industry standard — NeMo, OpenAI SDK, and LiteLLM all stop the pipeline immediately when a guardrail fires. Fail-fast is the expected default for safety-critical paths. | LOW | Pipeline iterates ordered policy list; first `{:halt, violation}` stops execution and returns `{:error, violation}` to the caller. No partial execution. |
| Request struct as pipeline context | All production guardrail systems (NeMo, LiteLLM, OpenAI SDK) pass a structured context object — not raw messages — through the chain. Policies need provider, messages, tools, and metadata in one place. | LOW | `%PhoenixAI.Guardrails.Request{}` with fields: `provider`, `model`, `messages`, `tools`, `opts`, `metadata`. Immutable — policies can read, never mutate. |
| PolicyViolation struct for structured errors | Consumers need machine-readable violation data: which policy fired, what the reason is, severity, and what was detected. Unstructured string errors are unusable in production monitoring. | LOW | `%PhoenixAI.Guardrails.PolicyViolation{}` with `policy`, `reason`, `severity`, `metadata`. Consistent with `PhoenixAI.Error` struct pattern already in library. |
| Jailbreak detection policy | Jailbreak detection is the single most cited table-stakes guardrail across every framework surveyed. Users attempting prompt injection is a known, common attack vector. | MEDIUM | `JailbreakDetection` policy wrapping a `JailbreakDetector` behaviour. Default implementation uses keyword/phrase matching against known injection patterns. |
| Content filter policy | Content filtering (pre-call and post-call) is the second most universal guardrail category. AWS Bedrock, Azure AI Content Safety, LiteLLM, and NeMo all provide it. | MEDIUM | `ContentFilter` policy with user-provided `pre_fn` and `post_fn` hooks that receive the request and return `:ok \| {:halt, reason}`. Pure callbacks — no built-in classifier required. |
| Tool policy (allowlist/denylist) | As agentic AI grows, controlling which tools an agent is permitted to call is table stakes for enterprise deployment. Every enterprise guardrails guide cites tool scoping as a primary control. | LOW | `ToolPolicy` with `mode: :allowlist \| :denylist` and `tools: [atom()]`. Checks `request.tools` list against config. Simple set membership check. |
| Ordered policy chain executor | All production systems (LiteLLM, NeMo, OpenAI SDK, Guardrails AI) execute policies as an ordered chain. Order determines priority and cost (cheap rules first, expensive LLM-based checks last). | LOW | `PhoenixAI.Guardrails.Pipeline.run(request, policies)` — simple `Enum.reduce_while` with halt on first violation. Returns `{:ok, request} \| {:error, violation}`. |
| Composable presets | AWS Bedrock, Azure AI Content Safety, and NeMo all expose named preset configurations (balanced, strict, permissive). Developers expect to pick a preset and configure from there, not assemble from scratch. | LOW | `:default`, `:strict`, `:permissive` atoms that resolve to an ordered list of `{policy_module, opts}` tuples. Consumers can use presets as a base and append/prepend their own policies. |

### Differentiators (Competitive Advantage)

Features that set this guardrails implementation apart from ad-hoc approaches and make it idiomatic for the Elixir/OTP ecosystem.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| JailbreakDetector behaviour (extensible) | Instead of hardcoding one jailbreak detection algorithm, expose a `JailbreakDetector` behaviour. Consumers can swap in regex-based, ML-based, or external API detectors without changing the policy. | MEDIUM | `@callback detect(text, opts) :: {:clean, score} \| {:jailbreak, score, patterns_matched}`. The default `KeywordDetector` ships with a curated pattern list. Mirrors the Plug behaviour-based extensibility pattern. |
| Scope configuration on JailbreakDetection | Different parts of a conversation need different sensitivity. Checking system prompts is different from checking user messages. NeMo distinguishes input/dialog/output rails — we expose `scope: :user \| :system \| :all` to match. | LOW | Filters which messages in `request.messages` are passed to the detector. `:user` checks only `role: "user"` messages. `:all` checks everything. Default: `:user`. |
| Threshold configuration for detection confidence | All production guardrail systems expose a confidence threshold (0.0–1.0). Allows teams to tune for their risk profile without changing the detector implementation. | LOW | `threshold: float()` in `JailbreakDetection` opts. Score from detector compared against threshold. Values closer to 0.0 are stricter. Default: 0.5. |
| Pure Elixir, zero ML dependencies | ML-based jailbreak detectors require Bumblebee/Nx, network calls to external APIs, or Python sidecars. The default `KeywordDetector` requires zero extra dependencies — pure Elixir pattern matching. Consumers opt into heavier detectors if needed. | LOW | The behaviour pattern allows consumers to plug in an ML classifier without the library mandating it. This is a library, not an app — zero mandatory heavy deps is a first-class concern. |
| Integration with existing PhoenixAI.Pipeline | Guardrails should be attachable to the existing sequential Pipeline as a pre-step, not a parallel system. Avoids forcing consumers to restructure existing pipeline code. | MEDIUM | `PhoenixAI.Guardrails.Pipeline.run/2` can be called as the first step of an existing Pipeline. The Request struct bridges the pipeline context cleanly. |
| Telemetry events for policy violations | Every guardrails firing is an observability event. Without telemetry, violations are invisible in production dashboards. Already part of library's telemetry integration established in v0.1.0. | LOW | Emit `[:phoenix_ai, :guardrails, :violation]` and `[:phoenix_ai, :guardrails, :pass]` events with policy module, severity, and metadata. |
| NimbleOptions-validated policy config | All existing PhoenixAI components use NimbleOptions. Policy opts should follow the same pattern — compile-time schema validation with readable error messages. | LOW | Each policy module defines an `opts_schema/0` function returning a NimbleOptions spec. `Pipeline.run/2` validates opts before executing. |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Built-in ML-based jailbreak classifier | Developers want high-accuracy jailbreak detection out of the box; ML models outperform keyword matching. | Mandates Bumblebee/Nx or external API as a hard dependency on the core library. Kills adoption for simple use cases. Adds 100+ MB of model weights. | Expose `JailbreakDetector` behaviour. Publish `phoenix_ai_ml_guards` as a separate optional library that implements the behaviour using Bumblebee. Document the pattern. |
| Post-call output guardrails (built-in) | NeMo, OpenAI SDK, and AWS Bedrock all have output rails. Checking AI responses for policy compliance is a real need. | Requires intercepting the response after the LLM call — which means the guardrails pipeline needs to be aware of both request and response lifecycles, significantly complicating the executor and the policy behaviour signature. | Scope this milestone to input (pre-call) guardrails only. Document that `ContentFilter`'s `post_fn` hook gives consumers a path to output filtering via the response callback. Output rails as a v0.4.0 item. |
| Rate limiting policy | Token budget and call rate limits are natural guardrails that developers expect to configure alongside jailbreak detection. | Stateful — requires a counter store (ETS, Redis, or DB) with TTL semantics. The PRD explicitly puts TokenBudget and CostBudget in `phoenix_ai_store`. Stateful policies in a stateless library create hidden state problems. | Document that stateful policies live in `phoenix_ai_store`. Provide a `Policy` behaviour that `phoenix_ai_store` implements for its rate-limiting policies, so the same executor works. |
| PII detection/masking built-in | Masking emails, phone numbers, and SSNs before sending to LLMs is a real enterprise need and a common guardrails feature (AWS Bedrock, Azure). | Regex-based PII detection has significant false-positive/false-negative rates and varies heavily by locale. A built-in implementation would create a false sense of security. | `ContentFilter` with a user-provided `pre_fn` is the correct primitive. Consumers can plug in a proper PII library (e.g., a NIF or external API) via the callback. |
| Guardrails DSL / configuration language | NeMo uses Colang — a custom DSL for defining guardrails. Developers familiar with NeMo might expect a declarative config format. | Colang exists because Python lacks composable module patterns. Elixir behaviours + keyword list config are already declarative and composable. A custom DSL adds parsing overhead and a new language to learn. | Plain Elixir module + NimbleOptions config IS the DSL. Keep it idiomatic. |
| Automatic retry on violation | When a guardrail fires, some frameworks (Guardrails AI's `on_fail: :fix`) attempt to rewrite the input and retry. | Retry-on-violation hides failures from the caller and can create infinite loops. It also conflates content rewriting (a different concern) with policy enforcement. | Return `{:error, %PolicyViolation{}}` and let the caller decide. If retry is needed, the caller can implement it explicitly with their own logic. |

---

## Feature Dependencies

```
PhoenixAI.Guardrails.Request (struct)
  └──required by──> PhoenixAI.Policy (behaviour)
                        └──required by──> PhoenixAI.Guardrails.Pipeline (executor)
                                            ├──required by──> JailbreakDetection policy
                                            ├──required by──> ContentFilter policy
                                            └──required by──> ToolPolicy policy

PhoenixAI.Guardrails.PolicyViolation (struct)
  └──required by──> PhoenixAI.Policy (halt return type)

PhoenixAI.Guardrails.JailbreakDetector (behaviour)
  └──required by──> PhoenixAI.Guardrails.Detectors.KeywordDetector (default impl)
                        └──required by──> JailbreakDetection policy (default detector)

JailbreakDetection + ContentFilter + ToolPolicy (policies)
  └──all required before──> Presets (:default, :strict, :permissive)

PhoenixAI.Guardrails.Pipeline (executor)
  └──integrates with──> PhoenixAI.Agent (pre-call hook site)
  └──integrates with──> PhoenixAI.Pipeline (first step pattern)
```

### Dependency Notes

- **Request struct before Policy behaviour:** `check/2` receives a `Request.t()` — the struct definition must be stable before any policy can be implemented or tested.
- **PolicyViolation before Pipeline:** The executor's halt branch returns `{:error, %PolicyViolation{}}` — the struct must exist before the executor can compile.
- **JailbreakDetector before JailbreakDetection:** The policy wraps the detector behaviour; the detector contract must be defined before the policy can delegate to it.
- **All three policies before Presets:** Presets reference policy modules by atom — all three must compile successfully before preset resolution works.
- **Executor before Agent integration:** The `PhoenixAI.Agent` integration is a post-milestone concern (wiring guardrails into the Agent GenServer lifecycle). The executor must be stable as a standalone first.

---

## MVP Definition

### Launch With (v0.3.0)

Minimum viable guardrails system — everything below must ship together to be coherent.

- [x] `%PhoenixAI.Guardrails.Request{}` struct — pipeline context carrier
- [x] `%PhoenixAI.Guardrails.PolicyViolation{}` struct — structured halt reason
- [x] `PhoenixAI.Policy` behaviour — `check/2` callback contract
- [x] `PhoenixAI.Guardrails.Pipeline` executor — ordered chain with halt-on-first-violation
- [x] `PhoenixAI.Guardrails.JailbreakDetector` behaviour — extensible detector contract
- [x] `PhoenixAI.Guardrails.Detectors.KeywordDetector` — default keyword/phrase heuristic
- [x] `PhoenixAI.Guardrails.Policies.JailbreakDetection` — wraps detector with scope/threshold config
- [x] `PhoenixAI.Guardrails.Policies.ContentFilter` — pre/post user-provided function hooks
- [x] `PhoenixAI.Guardrails.Policies.ToolPolicy` — allowlist/denylist for tool names
- [x] `PhoenixAI.Guardrails.Presets` — `:default`, `:strict`, `:permissive` resolvers

### Add After Validation (v0.3.x)

- [ ] Agent integration — wire `Guardrails.Pipeline.run/2` into `PhoenixAI.Agent` as an optional pre-call hook — adds `guardrails:` opt to `start_link/1`
- [ ] Telemetry events for pass/violation — `[:phoenix_ai, :guardrails, :violation]`
- [ ] `opts_schema/0` on each policy for NimbleOptions validation

### Future Consideration (v0.4+)

- [ ] Output rails — post-call response inspection via a second `check_output/2` callback on the policy behaviour
- [ ] `phoenix_ai_ml_guards` companion library — implements `JailbreakDetector` with a Bumblebee-based model
- [ ] Custom preset builder macro — `use PhoenixAI.Guardrails.Preset, base: :strict` to extend a preset

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Request + PolicyViolation structs | HIGH | LOW | P1 |
| Policy behaviour (`check/2`) | HIGH | LOW | P1 |
| Pipeline executor (ordered chain, halt) | HIGH | LOW | P1 |
| JailbreakDetector behaviour | HIGH | LOW | P1 |
| KeywordDetector (default impl) | HIGH | LOW | P1 |
| JailbreakDetection policy | HIGH | MEDIUM | P1 |
| ContentFilter policy | HIGH | LOW | P1 |
| ToolPolicy | HIGH | LOW | P1 |
| Presets (:default, :strict, :permissive) | MEDIUM | LOW | P1 |
| Agent integration (guardrails in GenServer) | HIGH | MEDIUM | P2 |
| Telemetry events | MEDIUM | LOW | P2 |
| NimbleOptions validation on policy opts | MEDIUM | LOW | P2 |
| Output rails | HIGH | HIGH | P3 |
| ML-based jailbreak detector | MEDIUM | HIGH | P3 (separate lib) |

**Priority key:**
- P1: Must have for v0.3.0 launch — this is the entire point of the milestone
- P2: Should have, add in v0.3.x patch
- P3: Nice to have / future milestone / companion library

---

## Competitor Feature Analysis

| Feature | NeMo Guardrails | OpenAI Agents SDK | LiteLLM | Guardrails AI | PhoenixAI v0.3.0 |
|---------|-----------------|-------------------|---------|---------------|------------------|
| Policy/guard interface | Colang + Python callbacks | `@input_guardrail` decorator | `CustomGuardrail` class with hooks | `Validator` class | `PhoenixAI.Policy` behaviour |
| Halt semantics | Yes — input rail rejection stops pipeline | Yes — tripwire raises exception | Yes — pre-call hook can block | Yes — `on_fail: :exception` | Yes — `{:halt, violation}` stops chain |
| Execution model | Ordered rail stages (input → dialog → retrieval → output) | Parallel or blocking | Hook points (pre\_call, post\_call, stream) | Sequential validator chain | Ordered `Enum.reduce_while` |
| Jailbreak detection | Yes — built-in + self-check | Via input guardrail + LLM classifier | Via `LlamaGuard`, `PromptShield` | Via validator hub | `JailbreakDetection` policy + `KeywordDetector` |
| Content filtering | Yes — output rail | Yes — output guardrail | Yes — `litellm_content_filter` | Yes — toxicity validator | `ContentFilter` with `pre_fn`/`post_fn` |
| Tool policy | No explicit tool allowlist | Tool scoping via agent config | Via custom guardrail | No | `ToolPolicy` allowlist/denylist |
| Presets | No explicit presets | No | No | No | `:default`, `:strict`, `:permissive` |
| Extensible detector | Via custom action Python | Custom class | Custom class | Custom validator | `JailbreakDetector` behaviour |
| Idiomatic language | Python + Colang DSL | Python decorator | Python class | Python class | Elixir behaviour + keyword config |
| Stateful policies | Yes (dialog state) | No | Yes (rate limits) | No | Deferred to `phoenix_ai_store` |
| Dependencies | Heavy (Python + optional LLM) | Python SDK | Python + optional models | Python | Pure Elixir — zero new deps |

**Key insight:** No existing Elixir library provides a structured guardrails policy system. The design is informed by what works across Python frameworks but adapted to Elixir idioms: behaviours replace abstract classes, Plug-style halt semantics replace exceptions, and `{:ok, _} | {:error, _}` tuples replace raising.

---

## Behavior Patterns: Expected Semantics

### Policy `check/2` contract

```elixir
@callback check(
  request :: PhoenixAI.Guardrails.Request.t(),
  opts :: keyword()
) :: :ok | {:halt, PhoenixAI.Guardrails.PolicyViolation.t()}
```

- `:ok` — policy passed, continue to next policy in chain
- `{:halt, violation}` — policy failed, stop chain, return `{:error, violation}` to caller
- Policies must not raise — they return structured tuples (consistent with library convention)
- Policies are stateless — no process state, no ETS, no side effects beyond the return value

### Pipeline executor contract

```elixir
@spec run(
  request :: PhoenixAI.Guardrails.Request.t(),
  policies :: [{module(), keyword()}]
) :: {:ok, PhoenixAI.Guardrails.Request.t()} | {:error, PhoenixAI.Guardrails.PolicyViolation.t()}
```

- Receives a list of `{PolicyModule, opts}` tuples — order is significant
- Returns `{:ok, request}` when all policies pass — request is unchanged (policies are read-only)
- Returns `{:error, violation}` on first `{:halt, violation}` — short-circuits remaining policies
- Cheap policies (keyword matching) should precede expensive policies (LLM classifiers) in the list

### Preset resolution

```elixir
PhoenixAI.Guardrails.Presets.resolve(:strict)
# => [
#   {PhoenixAI.Guardrails.Policies.JailbreakDetection, [threshold: 0.3, scope: :all]},
#   {PhoenixAI.Guardrails.Policies.ToolPolicy, [mode: :denylist, tools: []]},
#   {PhoenixAI.Guardrails.Policies.ContentFilter, [pre_fn: nil, post_fn: nil]}
# ]
```

- Presets return `[{module, opts}]` lists, not opaque objects — consumers can inspect and override
- `:default` — jailbreak detection (user messages, threshold 0.5) + tool policy (no-op / passthrough)
- `:strict` — jailbreak detection (all messages, threshold 0.3) + tool policy (allowlist mode, empty) + content filter (user hooks)
- `:permissive` — minimal jailbreak detection (user messages, threshold 0.8) — almost no blocking

---

## Sources

- [NeMo Guardrails documentation](https://docs.nvidia.com/nemo/guardrails/latest/index.html) — HIGH confidence (official NVIDIA docs)
- [OpenAI Agents SDK Guardrails](https://openai.github.io/openai-agents-python/guardrails/) — HIGH confidence (official OpenAI docs)
- [LiteLLM Custom Guardrail docs](https://docs.litellm.ai/docs/proxy/guardrails/custom_guardrail) — MEDIUM confidence (official LiteLLM docs)
- [Guardrails AI introduction](https://guardrailsai.com/docs) — MEDIUM confidence (official Guardrails AI docs)
- [LangChain Guardrails](https://docs.langchain.com/oss/python/langchain/guardrails) — MEDIUM confidence (official LangChain docs)
- [Plug halt semantics](https://hexdocs.pm/plug/Plug.Conn.html) — HIGH confidence (official Hex docs)
- [Plug behaviour](https://hexdocs.pm/plug/Plug.html) — HIGH confidence (official Hex docs)
- [AI Guardrails Production Implementation Guide 2026](https://iterathon.tech/blog/ai-guardrails-production-implementation-guide-2026) — LOW confidence (blog, WebSearch only)
- [Practical AI Guardrails: Types, Tools & Detection Methods](https://www.tredence.com/blog/ai-guardrails-types-tools-detection) — LOW confidence (blog, WebSearch only)
- [Guardrails for AI Agents — Weights & Biases](https://wandb.ai/site/articles/guardrails-for-ai-agents/) — LOW confidence (blog, WebSearch only)
- [Agentic AI Safety Playbook 2025](https://dextralabs.com/blog/agentic-ai-safety-playbook-guardrails-permissions-auditability/) — LOW confidence (blog, WebSearch only)

---

*Feature research for: AI Guardrails policy system (phoenix_ai v0.3.0)*
*Researched: 2026-04-04*
