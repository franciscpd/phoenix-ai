# Stack Research

**Domain:** Elixir AI Library — Middleware-chain Guardrails Policy System (v0.3.0)
**Researched:** 2026-04-04
**Confidence:** HIGH for existing stack; MEDIUM for ecosystem findings (guardrails space is early)

---

## Context: What Already Exists

The v0.2.0 stack (verified, shipped) is:

| Dependency | Version | Role |
|------------|---------|------|
| `req` | ~> 0.5 | HTTP client |
| `jason` | ~> 1.4 | JSON |
| `nimble_options` | ~> 1.1 | Config validation |
| `telemetry` | ~> 1.3 | Instrumentation |
| `finch` | ~> 0.19 | SSE streaming |
| `server_sent_events` | ~> 0.2 | SSE parsing |

This research answers only: **what new dependencies does the guardrails system need?**

---

## Recommended Stack for v0.3.0 Guardrails

### Core Technologies (NEW — adds to existing stack)

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| None | — | — | No new runtime dependencies are needed. All guardrails implementation uses Elixir stdlib + existing deps. |

**This is the correct answer.** Elixir's stdlib provides everything needed:

- `Enum.reduce_while/3` — halting pipeline executor (built-in)
- `Regex` + `:re` module — PCRE pattern matching for keyword detection (built-in)
- `String` module — text normalization, downcasing, trim (built-in)
- `@behaviour` + `@callback` — Policy and JailbreakDetector contracts (built-in)
- `defstruct` — Request, PolicyViolation structs (built-in)
- `NimbleOptions` (already a dep) — policy config schema validation

### Supporting Libraries (EVALUATED — do not add)

| Library | Version | Status | Reason |
|---------|---------|--------|--------|
| `pluggable` | 1.1.0 | DO NOT ADD | Plug-like pipeline for arbitrary tokens. 94,604 all-time downloads, 0 deps. Elegant API, but adds a dep for something `Enum.reduce_while/3` already handles cleanly. Only add if pipeline grows to multi-stage with assigns/shared state. |
| `llm_guard` | 0.3.1 | DO NOT ADD | Alpha-status (434 all-time downloads). 97.4% tests passing (not 100%). Prompts injection detection with 34+ patterns and jailbreak detection. Too early-stage to depend on, but use as **reference for keyword/pattern lists** only. |

### Development Tools (UNCHANGED)

| Tool | Purpose | Notes |
|------|---------|-------|
| `mox` | Mock `Policy` and `JailbreakDetector` behaviours in tests | Already in dev deps; works perfectly with the `@callback` pattern |
| `excoveralls` | Coverage tracking | Already in dev deps |
| `credo` | Code style | Already in dev deps |
| `dialyxir` | Type checking | Already in dev deps — critical for catching `@spec` issues in behaviour callbacks |

---

## Pipeline Executor: Stdlib Pattern

The pipeline executor (`PhoenixAI.Guardrails.Pipeline.run/2`) should be implemented with `Enum.reduce_while/3`. This is idiomatic Elixir, has zero overhead, and maps cleanly to the halt-on-first-violation semantic:

```elixir
def run(policies, request) do
  Enum.reduce_while(policies, {:ok, request}, fn policy, {:ok, req} ->
    case policy.check(req, policy_opts(policy)) do
      :ok -> {:cont, {:ok, req}}
      {:halt, %PolicyViolation{} = violation} -> {:halt, {:error, violation}}
    end
  end)
end
```

**Why not `pluggable`?** Pluggable is designed for pipelines that accumulate shared state via `:assigns` and need a `halted` flag on the token struct. Our pipeline is simpler: it runs policies in order and stops at the first violation. `Enum.reduce_while/3` expresses this without an extra library.

**Why not `Plug.Builder`?** Requires `%Plug.Conn{}` — wrong domain. Would drag in the Plug dependency (a Phoenix concern) into a library that is explicitly Phoenix-independent.

---

## JailbreakDetector: Stdlib Pattern

The default `KeywordDetector` should use compiled `Regex` patterns:

```elixir
@jailbreak_patterns [
  ~r/ignore (all |previous |prior )?(instructions?|prompts?|rules?)/i,
  ~r/you are now (in )?DAN mode/i,
  ~r/pretend (you (are|have)|to be) (a |an )?(different|unrestricted|evil)/i,
  ~r/roleplay as/i,
  ~r/forget (your|all) (training|guidelines|restrictions)/i,
  # ... more patterns from llm_guard reference
]
```

Pattern matching at this scale (<50 patterns, <2KB text inputs) is microseconds. No external NLP library is needed. PCRE via Elixir's built-in `:re` module is sufficient.

**Why not ML-based detection?** `Nx` + `Bumblebee` would add a 300MB+ dependency footprint with GPU/CUDA requirements. The `JailbreakDetector` behaviour allows consumers to plug in ML-based implementations — the default stays fast and zero-dep.

---

## NimbleOptions: Policy Config Validation

NimbleOptions (already a dep at `~> 1.1`) supports nested schemas — use it for policy configuration:

```elixir
@policy_schema NimbleOptions.new!([
  policies: [
    type: {:list, :any},
    default: [],
    doc: "List of policy modules to run in order"
  ],
  jailbreak_detection: [
    type: :keyword_list,
    keys: [
      scope: [type: {:in, [:user, :all, :system]}, default: :user],
      threshold: [type: :float, default: 0.8]
    ]
  ]
])
```

Nested keyword_list validation is supported by NimbleOptions v1.1.x (HIGH confidence — verified in official docs).

---

## Installation

No new packages. The guardrails system is pure Elixir + existing deps.

The only mix.exs changes needed are adding the new modules to `groups_for_modules` in docs configuration:

```elixir
groups_for_modules: [
  # ... existing groups ...
  Guardrails: [
    PhoenixAI.Guardrails,
    PhoenixAI.Guardrails.Policy,
    PhoenixAI.Guardrails.Pipeline,
    PhoenixAI.Guardrails.Request,
    PhoenixAI.Guardrails.PolicyViolation,
    PhoenixAI.Guardrails.Policies.JailbreakDetection,
    PhoenixAI.Guardrails.Policies.ContentFilter,
    PhoenixAI.Guardrails.Policies.ToolPolicy,
    PhoenixAI.Guardrails.Detectors.JailbreakDetector,
    PhoenixAI.Guardrails.Detectors.KeywordDetector,
    PhoenixAI.Guardrails.Presets,
  ]
]
```

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| `Enum.reduce_while/3` (stdlib) | `pluggable ~> 1.1` | Use pluggable only if the pipeline grows to require shared assigns across steps, or if halted-flag semantics on the token struct become necessary |
| Custom keyword/regex detector | `llm_guard ~> 0.3` | Use llm_guard when it reaches stable (1.0+) and production download counts; currently 434 total downloads — too early for a library dependency |
| Pure pattern matching | `Nx` + `Bumblebee` | Use Bumblebee if consumers need ML-based semantic jailbreak detection — expose via the `JailbreakDetector` behaviour so it's opt-in |
| NimbleOptions (already dep) | `Ecto.embedded_schema` | Use Ecto if policy options need full changeset validation and user-facing error messages at the Phoenix layer; NimbleOptions is appropriate for library-internal config |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `llm_guard` as a runtime dep | 434 all-time downloads, alpha status (0.3.1), 97.4% test pass rate. Risk of breaking changes, abandoned library. | Borrow its keyword/regex pattern lists as reference, implement natively |
| `plug` / `Plug.Builder` | Requires `%Plug.Conn{}`, pulls in Phoenix concern into a Phoenix-independent library | `Enum.reduce_while/3` expresses the same halt semantics cleanly |
| `Nx` / `Bumblebee` as default | 300MB+ footprint, GPU requirements, incompatible with "zero-dep runtime" library philosophy | Expose `JailbreakDetector` behaviour so ML detection is consumer-pluggable |
| `tesla` middleware pattern | Adapter boilerplate, not needed when policy chain is pure data transformation | Plain function pipeline with `reduce_while` |
| External content moderation APIs | Network latency, API key required, defeats offline-capable guardrails | Compile-time regex patterns in `KeywordDetector` |

---

## Stack Patterns by Variant

**If consumer wants ML-based jailbreak detection:**
- Implement `PhoenixAI.Guardrails.Detectors.JailbreakDetector` behaviour
- Use Bumblebee text classification model as the backend
- Wire it into `JailbreakDetection` policy via `:detector` option
- No changes to library internals needed

**If consumer wants external moderation API (OpenAI Moderation, etc.):**
- Implement `PhoenixAI.Guardrails.Policy` behaviour directly
- Call moderation API in `check/2` callback
- Return `{:halt, PolicyViolation.new(...)}` on flagged content
- Library provides the contract; consumer owns the integration

**If consumer wants stateful policies (token budget, cost budget):**
- These belong in `phoenix_ai_store`, not here
- `phoenix_ai_store` implements the `Policy` behaviour against its DB/state
- PhoenixAI core remains stateless

---

## Version Compatibility

| Package | Compatible With | Notes |
|---------|-----------------|-------|
| `nimble_options ~> 1.1` | Elixir ~> 1.14 | Nested `:keyword_list` type available since NimbleOptions 1.0 |
| `Enum.reduce_while/3` | Elixir 1.0+ | Stdlib, no version concern |
| `Regex` PCRE | Elixir 1.0+ | Backed by PCRE via Erlang `:re` — fully Unicode-aware with `u` modifier |

---

## Ecosystem Findings: Elixir Guardrails Space

The Elixir guardrails ecosystem is **very early stage** as of 2026-04-04:

- **`llm_guard` (v0.3.1)** — North-Shore-AI. The only dedicated Elixir guardrails library. Alpha-status, 434 all-time downloads, ~94/month. Pattern-based approach (34+ prompt injection patterns). Pipeline architecture using config toggles. **Architectural learning:** their detector-as-module pattern maps well to our `JailbreakDetector` behaviour.

- **`pluggable` (v1.1.0)** — mruoss. Plug-like middleware for arbitrary tokens. 94,604 all-time downloads, 4 dependants. Mature and well-designed. Not needed for our use case but validates the "halted token" pattern as an established Elixir idiom.

- **LangChain.ex message processors** — Uses `:cont` / `:halt` tuple returns from processor functions. Same pattern as `Enum.reduce_while/3`. Validates our approach.

**Conclusion:** No mature Elixir library exists for the guardrails use case. PhoenixAI v0.3.0 will be among the first production-ready implementations in the ecosystem. The implementation should be self-contained using stdlib primitives — no external guardrails dependency is appropriate at this time.

---

## Sources

- [llm_guard - Hex.pm](https://hex.pm/packages/llm_guard) — v0.3.1, 434 all-time downloads (MEDIUM confidence — alpha)
- [North-Shore-AI/LlmGuard - GitHub](https://github.com/North-Shore-AI/LlmGuard) — pipeline architecture reference
- [pluggable - Hex.pm](https://hex.pm/packages/pluggable) — v1.1.0, 94,604 all-time downloads (HIGH confidence)
- [mruoss/pluggable - GitHub](https://github.com/mruoss/pluggable) — Pluggable.Token protocol, StepBuilder, halt semantics
- [NimbleOptions v1.1.1 - HexDocs](https://hexdocs.pm/nimble_options/NimbleOptions.html) — nested :keyword_list type verified
- [Plug.Builder - HexDocs](https://hexdocs.pm/plug/Plug.Builder.html) — halt semantics reference (not used)
- [Enum.reduce_while - HexDocs](https://hexdocs.pm/elixir/Enum.html#reduce_while/3) — pipeline executor pattern
- [Elixir Regex - HexDocs](https://hexdocs.pm/elixir/Regex.html) — PCRE pattern matching, Unicode support
- [Behaviours - Elixir School](https://elixirschool.com/en/lessons/advanced/behaviours) — @callback pattern reference

---
*Stack research for: PhoenixAI v0.3.0 Guardrails Milestone*
*Researched: 2026-04-04*
