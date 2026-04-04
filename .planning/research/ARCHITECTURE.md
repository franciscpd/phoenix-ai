# Architecture Research

**Domain:** Elixir AI Library — Middleware-Chain Guardrails Policy System
**Researched:** 2026-04-04
**Confidence:** HIGH

---

## Context: Adding Guardrails to an Existing Library

This document focuses on the guardrails integration architecture for v0.3.0. The base
architecture (layered provider/adapter/agent/pipeline structure) is already established and
validated. The question here is: how does a new policy pipeline layer wire into `chat/2`,
`stream/2`, and the `Agent`, without breaking existing call sites?

---

## Standard Architecture

### System Overview — Guardrails as a Pre-Call Gate

```
┌─────────────────────────────────────────────────────────────────┐
│                       CONSUMER CALL SITE                         │
│  PhoenixAI.chat/2  PhoenixAI.Agent.prompt/3  PhoenixAI.stream/3 │
└─────────────────────────┬───────────────────────────────────────┘
                          │ opts: [guardrails: [policies: [...]]]
                          ↓
┌─────────────────────────────────────────────────────────────────┐
│                 GUARDRAILS PIPELINE (pre-call gate)              │
│                                                                  │
│  Guardrails.Pipeline.run(request, policies)                      │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ [JailbreakDetection, ContentFilter, ToolPolicy, ...]      │   │
│  │  each implements Policy behaviour: check(request, opts)   │   │
│  │  returns {:ok, request} | {:halt, %PolicyViolation{}}     │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────┬───────────────────────────────────────┘
                          │ {:ok, _} continues  {:halt, _} returns early
                          ↓
┌─────────────────────────────────────────────────────────────────┐
│                   PROVIDER ADAPTER LAYER                         │
│   Providers.OpenAI  Providers.Anthropic  Providers.OpenRouter    │
└─────────────────────────────────────────────────────────────────┘
```

Guardrails runs as a pure, synchronous gate between the consumer call site and the
provider adapter. It does not wrap the provider in a process; it is a function call that
returns early on violation or passes through on success.

---

### Component Responsibilities — New vs. Existing

| Component | New/Existing | Responsibility |
|-----------|-------------|----------------|
| `Guardrails.Policy` (behaviour) | NEW | Contract every policy module must implement |
| `Guardrails.Request` (struct) | NEW | Context struct flowing through the policy chain |
| `Guardrails.PolicyViolation` (struct) | NEW | Structured error returned on halt |
| `Guardrails.Pipeline` | NEW | Executes ordered policy list with halt-on-first semantics |
| `Guardrails.Presets` | NEW | Named policy lists (`:default`, `:strict`, `:permissive`) |
| `Policies.JailbreakDetection` | NEW | Wraps `JailbreakDetector` behaviour |
| `Policies.ContentFilter` | NEW | Pre/post user-provided function hooks |
| `Policies.ToolPolicy` | NEW | Allowlist/denylist for tool calls |
| `JailbreakDetector` (behaviour) | NEW | Contract for jailbreak detection implementations |
| `JailbreakDetector.Default` | NEW | Keyword heuristic implementation |
| `Provider.chat/2` | EXISTING — unchanged | Receives messages only after guardrails pass |
| `Provider.stream/3` | EXISTING — unchanged | Same; guardrails run before stream opens |
| `Agent.handle_call/3` | MODIFIED | Runs guardrails before dispatching to provider |

---

## Recommended Project Structure

```
lib/
└── phoenix_ai/
    └── guardrails/
        ├── policy.ex                   # @behaviour with check/2 callback
        ├── request.ex                  # %Request{} struct — pipeline context
        ├── policy_violation.ex         # %PolicyViolation{} struct
        ├── pipeline.ex                 # run/2 — Enum.reduce_while executor
        ├── presets.ex                  # Named policy lists
        ├── jailbreak_detector.ex       # @behaviour for detector implementations
        ├── jailbreak_detector/
        │   └── default.ex             # Keyword heuristics implementation
        └── policies/
            ├── jailbreak_detection.ex  # Policy wrapping JailbreakDetector
            ├── content_filter.ex       # Pre/post hook policy
            └── tool_policy.ex          # Allowlist/denylist policy
```

### Structure Rationale

- **`guardrails/` as a namespace:** All guardrail modules live under one namespace so
  the surface area is clear and the entire subsystem can be understood at a glance.
- **`policies/` subfolder:** Concrete policy implementations are separated from
  infrastructure (`policy.ex`, `pipeline.ex`), allowing new policies to be added without
  touching core files.
- **`jailbreak_detector/` subfolder:** The `JailbreakDetector` behaviour has its own
  subfolder for multiple implementations (default keyword, future ML-based, etc.) without
  cluttering the policies folder.
- **`presets.ex` as a module function:** Rather than a macro DSL, presets are plain
  functions returning keyword lists — zero magic, easy to inspect and override.

---

## Architectural Patterns

### Pattern 1: `@behaviour` with `{:ok, request} | {:halt, violation}` Return Contract

**What:** Every policy module implements `PhoenixAI.Guardrails.Policy` by defining a
single `check/2` callback. The callback receives a `Request` struct and a keyword options
list, and returns either `{:ok, %Request{}}` (continue) or `{:halt, %PolicyViolation{}}`
(stop the chain).

**When to use:** This is the only extension point for new policies. Use it for any pre-call
validation that should block the provider call.

**Trade-offs:**
- Pros: Simple contract, compile-time warnings if callback not implemented, no GenServer
  needed, pure functions are easy to test in isolation.
- Cons: Cannot modify the request in-place and continue (no "transform and continue" path)
  — but this is intentional; policies that modify requests become difficult to reason about.

**Example:**

```elixir
defmodule PhoenixAI.Guardrails.Policy do
  @moduledoc "Behaviour for all guardrail policies."

  @callback check(
              request :: PhoenixAI.Guardrails.Request.t(),
              opts :: keyword()
            ) ::
              {:ok, PhoenixAI.Guardrails.Request.t()}
              | {:halt, PhoenixAI.Guardrails.PolicyViolation.t()}
end
```

Note: `@callback` not `@spec` because this is a behaviour contract, not a type spec on a
concrete function. Each implementing module also declares `@behaviour PhoenixAI.Guardrails.Policy`
and uses `@impl true` on its `check/2`.

---

### Pattern 2: `Enum.reduce_while` Pipeline — Halt-on-First-Violation

**What:** `Guardrails.Pipeline.run/2` iterates the ordered list of `{module, opts}` tuples
using `Enum.reduce_while`. The accumulator is `{:ok, request}`. On the first
`{:halt, violation}`, `reduce_while` stops and returns `{:halt, violation}` to the caller.
All policies after the halted one are skipped.

**When to use:** This is the core execution engine. Do not replace with `Task.async_stream`
— policies must run serially and in order (each may depend on previous policy state or
request annotations).

**Trade-offs:**
- Pros: Idiomatic Elixir, consistent with existing `Pipeline.run/3`, no OTP overhead.
- Cons: No parallel policy execution (acceptable — policy checks are fast, sub-millisecond
  for keyword heuristics; if an ML-based policy is added later it becomes its own opt-in
  strategy).

**Example:**

```elixir
defmodule PhoenixAI.Guardrails.Pipeline do
  alias PhoenixAI.Guardrails.{PolicyViolation, Request}

  @spec run(Request.t(), [{module(), keyword()}]) ::
          {:ok, Request.t()} | {:halt, PolicyViolation.t()}
  def run(%Request{} = request, policies) do
    start_time = System.monotonic_time()

    result =
      Enum.reduce_while(policies, {:ok, request}, fn {policy_mod, opts}, {:ok, req} ->
        case policy_mod.check(req, opts) do
          {:ok, updated_req} -> {:cont, {:ok, updated_req}}
          {:halt, violation} -> {:halt, {:halt, violation}}
        end
      end)

    duration = System.monotonic_time() - start_time
    status = if match?({:ok, _}, result), do: :ok, else: :halted

    :telemetry.execute(
      [:phoenix_ai, :guardrails, :pipeline],
      %{duration: duration},
      %{policy_count: length(policies), status: status}
    )

    result
  end
end
```

---

### Pattern 3: `Request` Struct as Pipeline Context (Not `Plug.Conn`)

**What:** A dedicated `%Guardrails.Request{}` struct carries all context needed by any
policy: the messages list, the tool modules list, provider, and an `assigns` map for
policy-to-policy communication (following Exq.Middleware.Pipeline's `assigns` pattern).

**When to use:** Always. Do not pass raw keyword lists or individual parameters — the struct
allows policies to annotate the request for downstream policies without modifying function
signatures.

**Why not `Plug.Conn`:** `Plug.Conn` is Phoenix/Cowboy-specific and would create a
hard dependency on a web framework. `Request` is a plain Elixir struct with no deps.

**Example:**

```elixir
defmodule PhoenixAI.Guardrails.Request do
  @moduledoc "Pipeline context for guardrail policy evaluation."

  @type t :: %__MODULE__{
          messages: [PhoenixAI.Message.t()],
          tools: [module()],
          provider: atom(),
          model: String.t() | nil,
          assigns: map()
        }

  defstruct [
    :provider,
    :model,
    messages: [],
    tools: [],
    assigns: %{}
  ]
end
```

The `assigns` map allows policies to annotate: for example, `JailbreakDetection` could
set `assigns.jailbreak_score` so a downstream logging policy can read it without re-running
detection.

---

### Pattern 4: Integration via `with` in `chat/2` and `Agent.handle_call/3`

**What:** Guardrails run inside a `with` chain before the provider call. If guardrails halt,
the `{:halt, violation}` is mapped to `{:error, violation}` and returned to the caller
immediately. If they pass, the request flows to the provider unchanged.

**When to use:** This is the wiring pattern. The `opts` keyword list gains a `:guardrails`
key that accepts a keyword list with `:policies` and `:preset` sub-keys.

**Trade-offs:**
- Pros: No changes to provider adapters, no OTP changes, opt-in by default (nil guardrails
  = pass-through), backward compatible with all existing call sites.
- Cons: Guardrails cannot be applied post-response (output filtering) in this design. That
  is intentional for v0.3.0 scope — pre-call only.

**Example — wiring in a provider adapter (illustrative, not the actual location):**

```elixir
# In the provider adapter or a shared wrapper:
defp maybe_run_guardrails(messages, tools, provider, model, opts) do
  case Keyword.get(opts, :guardrails) do
    nil ->
      {:ok, messages}

    guardrail_opts ->
      request = %Guardrails.Request{
        messages: messages,
        tools: tools,
        provider: provider,
        model: model
      }

      policies = resolve_policies(guardrail_opts)

      case Guardrails.Pipeline.run(request, policies) do
        {:ok, _request} -> {:ok, messages}
        {:halt, violation} -> {:error, violation}
      end
  end
end

defp resolve_policies(opts) do
  case Keyword.get(opts, :preset) do
    nil -> Keyword.get(opts, :policies, [])
    preset -> Guardrails.Presets.get(preset)
  end
end
```

---

### Pattern 5: `JailbreakDetector` as a Second-Level Behaviour

**What:** The `JailbreakDetection` policy delegates detection to a `JailbreakDetector`
behaviour. The default implementation uses keyword heuristics. Consumers can swap in their
own detector (ML-based, API-backed) by pointing the policy config at a different module.

**When to use:** Whenever the detection logic itself needs to be replaceable independently
of the policy wrapper.

**Trade-offs:**
- Pros: Separates the "when to block" (policy) from "what counts as jailbreak" (detector).
  Testable in isolation. Consumers can upgrade detection without rewriting policy config.
- Cons: One extra layer of indirection; acceptable because the two concerns genuinely differ.

```elixir
defmodule PhoenixAI.Guardrails.JailbreakDetector do
  @moduledoc "Behaviour for jailbreak detection implementations."

  @callback detect(text :: String.t(), opts :: keyword()) ::
              {:safe, score :: float()}
              | {:jailbreak, score :: float(), reason :: String.t()}
end
```

---

## Data Flow

### Flow 1: `chat/2` with Guardrails (Happy Path)

```
Consumer
  → PhoenixAI.chat(messages, provider: :openai, guardrails: [preset: :default])
    → resolve provider module
    → build Guardrails.Request{messages: messages, provider: :openai, ...}
    → resolve preset policies → [JailbreakDetection, ContentFilter]
    → Guardrails.Pipeline.run(request, policies)
      → JailbreakDetection.check(request, []) → {:ok, request}
      → ContentFilter.check(request, []) → {:ok, request}
    ← {:ok, request}
    → provider_mod.chat(messages, opts_without_guardrails)
    ← {:ok, %Response{}}
  ← {:ok, %Response{}}
```

### Flow 2: `chat/2` with Guardrails (Halted Path)

```
Consumer
  → PhoenixAI.chat(messages, provider: :openai, guardrails: [preset: :strict])
    → resolve provider module
    → build Guardrails.Request{messages: messages, provider: :openai, ...}
    → resolve preset policies → [JailbreakDetection, ContentFilter, ToolPolicy]
    → Guardrails.Pipeline.run(request, policies)
      → JailbreakDetection.check(request, [])
        → JailbreakDetector.Default.detect(user_text, [])
        ← {:jailbreak, 0.92, "role-playing bypass detected"}
        ← {:halt, %PolicyViolation{policy: JailbreakDetection, reason: "...", score: 0.92}}
    ← {:halt, %PolicyViolation{}}
    ← {:error, %PolicyViolation{}}
  ← {:error, %PolicyViolation{}}
  (provider never called)
```

### Flow 3: `Agent.prompt/3` with Guardrails

```
Consumer
  → PhoenixAI.Agent.prompt(pid, "text", guardrails: [policies: [{JailbreakDetection, []}]])
    → GenServer.call/3 with {:prompt, text, opts}
    → Agent.handle_call/3
      → build user_msg = %Message{role: :user, content: text}
      → build messages = history ++ [user_msg]
      → extract guardrails from opts
      → build Guardrails.Request{messages: messages, tools: state.tools, ...}
      → Guardrails.Pipeline.run(request, policies)
        → {:ok, _} → continue; spawn Task for provider call
        → {:halt, violation} → GenServer.reply(from, {:error, violation}); no Task spawned
```

### Flow 4: `stream/3` with Guardrails

```
Consumer
  → provider_mod.stream(messages, callback, opts)
    → same pre-flight check as chat/2
    → guardrails pass → open Finch SSE connection
    → guardrails halt → {:error, %PolicyViolation{}} returned before Finch is invoked
```

---

### State Management

The guardrails pipeline is stateless. There is no GenServer, no ETS, no process.
Each call to `Guardrails.Pipeline.run/2` is a pure function call. The `assigns` map on
`Request` is the only in-flight state, scoped to a single pipeline execution.

Stateful policies (e.g., `TokenBudget`, `CostBudget`) are explicitly **out of scope** for
this library. They belong in `phoenix_ai_store` where persistence is available. This
constraint keeps the guardrails subsystem pure and easy to test.

---

## Integration Points

### New vs. Modified Components

| Component | Status | Change |
|-----------|--------|--------|
| `Guardrails.Policy` | NEW | Behaviour module, no existing file |
| `Guardrails.Request` | NEW | Struct, no existing file |
| `Guardrails.PolicyViolation` | NEW | Struct, no existing file |
| `Guardrails.Pipeline` | NEW | Not related to existing `PhoenixAI.Pipeline` |
| `Guardrails.Presets` | NEW | Helper module |
| `JailbreakDetector` behaviour | NEW | No existing file |
| `JailbreakDetector.Default` | NEW | No existing file |
| `Policies.JailbreakDetection` | NEW | No existing file |
| `Policies.ContentFilter` | NEW | No existing file |
| `Policies.ToolPolicy` | NEW | No existing file |
| `PhoenixAI.Agent` | MODIFIED | Add guardrails check before Task spawn |
| `PhoenixAI.providers/*.ex` | NOT MODIFIED | Adapters stay clean; no guardrails logic |
| `PhoenixAI.Stream` | NOT MODIFIED | Guardrails run before Stream.run is called |

### Where Guardrails Wire In (Exact Points)

**`PhoenixAI.Agent.handle_call/3` — `:prompt` clause:**

```elixir
def handle_call({:prompt, text, msg_opts}, from, state) do
  user_msg = %Message{role: :user, content: text}
  messages = build_messages(state, user_msg, msg_opts)

  # NEW: guardrails gate
  guardrail_opts = Keyword.get(msg_opts, :guardrails)

  case run_guardrails(messages, state.tools, state.provider_atom, guardrail_opts) do
    {:ok, _} ->
      task = Task.async(fn ->
        if state.tools != [] do
          ToolLoop.run(state.provider_mod, messages, state.tools, state.opts)
        else
          state.provider_mod.chat(messages, state.opts)
        end
      end)
      {:noreply, %{state | pending: {from, task.ref}, pending_user_msg: user_msg}}

    {:error, violation} ->
      {:reply, {:error, violation}, state}
  end
end
```

**`PhoenixAI.providers/openai.ex` (and other adapters) — NOT modified:**

Provider adapters do not know about guardrails. The gate is upstream in the call chain.
This preserves the existing architecture: adapters speak only the provider's HTTP API.

---

## Comparison with Plug's Middleware Model

| Aspect | Plug | PhoenixAI Guardrails |
|--------|------|---------------------|
| Unit of middleware | Module with `init/1` + `call/2` | Module with `check/2` only |
| State carrier | `%Plug.Conn{}` (HTTP-specific) | `%Guardrails.Request{}` (AI-specific) |
| Halt mechanism | `conn.halted = true` flag + `Plug.Conn.halt/1` | `{:halt, violation}` tagged tuple |
| Pipeline executor | `Plug.Builder` (compile-time macro) | `Enum.reduce_while` (runtime, no macro) |
| Return value | Modified conn struct (always a conn) | `{:ok, request}` or `{:halt, violation}` |
| Phoenix dependency | Yes (inherent) | No — plain Elixir |
| Composability | `plug/2` macro, compile-time ordering | `[{mod, opts}]` list, runtime ordering |
| `init/1` pattern | Required — compile-time option transform | Not used — opts passed directly to check/2 |

**Why not use `Plug.Builder` directly:**

1. `Plug.Conn` is an HTTP-specific struct. Carrying HTTP state into an AI guardrail pipeline
   introduces a dependency on `plug` and couples AI safety logic to HTTP request lifecycle.
2. Plug's halt mechanism (`conn.halted`) is a flag on a mutable struct — subsequent plugs
   must check this flag manually unless using `Plug.Builder`. For a small, purpose-built
   pipeline, `reduce_while` with a tagged tuple is cleaner and more explicit.
3. `Plug.Builder` generates code at compile time; the policy list must be known at compile
   time or wrapped in runtime modules. PhoenixAI's guardrails must support runtime-configured
   policy lists (e.g., different presets per call site).

**What we borrow from Plug:**

- The `@behaviour` approach for middleware modules (same pattern Plug uses).
- The `assigns` map concept for inter-policy communication (from `Plug.Conn.assigns`).
- The "halt early, skip remaining" semantic (directly mirrored in `reduce_while`).

---

## Anti-Patterns

### Anti-Pattern 1: Putting Guardrail Logic in Provider Adapters

**What people do:** Add policy checks inside `OpenAI.chat/2` or `Anthropic.chat/2`.
**Why it's wrong:** Provider adapters would need to know about guardrails, violating their
single responsibility (translate between canonical structs and HTTP). Every new policy
would require modifying multiple adapter files.
**Do this instead:** Guardrails run in the caller's path, before the adapter is invoked.
Adapters receive only messages; they never see policy config.

### Anti-Pattern 2: Making the Pipeline a GenServer

**What people do:** Start a `GuardRail.Server` GenServer that holds policy state and
processes requests.
**Why it's wrong:** Introduces process bottleneck; every chat call would serialize through
one process. Stateful policies (rate limits, cost budgets) also need persistence, which
belongs in `phoenix_ai_store` not in-process state.
**Do this instead:** Keep `Guardrails.Pipeline.run/2` a pure function. Stateful policies
are out of scope and belong in a companion library.

### Anti-Pattern 3: Using Protocols Instead of Behaviours for Policy Modules

**What people do:** Define a `PhoenixAI.Guardrails.Policy` protocol with a `check/2`
function.
**Why it's wrong:** Protocols are for dispatching on data types — the "what are you?" 
question. Policies are modules with function implementations — the "what do you do?" 
question. Behaviours are the correct Elixir primitive for defining a module contract.
Additionally, behaviours give `@impl true` compile-time checks; protocols do not.
**Do this instead:** `@behaviour PhoenixAI.Guardrails.Policy` with `@callback check/2`.

### Anti-Pattern 4: Returning `{:error, reason}` from Policies Instead of `{:halt, violation}`

**What people do:** Define the callback as returning `{:ok, request} | {:error, reason}`.
**Why it's wrong:** `{:error, reason}` loses the structured `PolicyViolation` type, making
it impossible for callers to distinguish a guardrail block from a provider error. Both end
up as `{:error, _}` at the call site.
**Do this instead:** Policies return `{:halt, %PolicyViolation{}}`. The pipeline executor
maps this to `{:error, %PolicyViolation{}}` at the boundary. Callers can `match?(%PolicyViolation{}, reason)` to distinguish policy blocks from provider errors.

### Anti-Pattern 5: Coupling `JailbreakDetection` and `JailbreakDetector.Default` into One Module

**What people do:** Put the detection algorithm directly inside the policy module.
**Why it's wrong:** Consumers cannot swap detection logic independently. Testing the policy
requires testing the detection algorithm simultaneously.
**Do this instead:** The `JailbreakDetection` policy holds config and delegates to the
`JailbreakDetector` behaviour. `JailbreakDetector.Default` implements keyword heuristics.
Consumers can pass `detector: MyApp.MLDetector` in the policy opts.

---

## Suggested Build Order

This order respects dependency direction: each component can be built and tested before
anything that depends on it is written.

```
Phase 1 — Core Contracts (no deps on each other)
  1a. Guardrails.Request struct
  1b. Guardrails.PolicyViolation struct
  1c. Guardrails.Policy behaviour (@callback only)
  1d. JailbreakDetector behaviour (@callback only)

Phase 2 — Pipeline Executor
  2a. Guardrails.Pipeline.run/2 (depends on Request, PolicyViolation, Policy)
  2b. Telemetry event for pipeline execution

Phase 3 — Concrete Implementations
  3a. JailbreakDetector.Default (depends on JailbreakDetector behaviour)
  3b. Policies.JailbreakDetection (depends on Policy, JailbreakDetector)
  3c. Policies.ContentFilter (depends on Policy)
  3d. Policies.ToolPolicy (depends on Policy, Message.tool_calls shape)

Phase 4 — Presets
  4a. Guardrails.Presets (depends on all policies)

Phase 5 — Integration Wiring
  5a. Modify PhoenixAI.Agent.handle_call/3 to run guardrails before Task spawn
  5b. Document opt-in pattern for direct provider.chat/2 callers

Phase 6 — Tests
  6a. Unit tests for each policy in isolation
  6b. Unit tests for JailbreakDetector.Default keyword patterns
  6c. Integration test: Agent.prompt with guardrails preset
  6d. Integration test: policy violation returned as {:error, %PolicyViolation{}}
```

**Rationale:**

- Contracts (Phase 1) before implementations (Phase 3) — implementations cannot compile
  without their behaviour defined.
- `Pipeline.run/2` (Phase 2) before concrete policies (Phase 3) — the executor is the
  hardest-to-get-wrong piece; build it with stub policies first.
- Presets (Phase 4) after all policies exist — a preset is just a function returning a
  list of modules; it cannot reference modules that do not exist yet.
- Integration wiring (Phase 5) last — touches existing production code (`Agent`); doing it
  last minimizes the window where existing tests could be broken.

---

## Scaling Considerations

This system is a pre-call function chain, not a process topology. Scaling concerns are
minimal for v0.3.0 because:

| Scale | Architecture Impact |
|-------|---------------------|
| 0-10K concurrent requests | None — each `Guardrails.Pipeline.run/2` runs in the caller's process, no shared state |
| 10K-1M requests | Keyword heuristics stay fast (~microseconds per call); no bottleneck |
| ML-based detector added | Detector is a behaviour; add a new module implementing it, no pipeline changes |
| Stateful rate-limiting needed | Do not add to this library; implement in `phoenix_ai_store` using ETS or Ecto |

---

## Sources

| Source | Confidence | Used For |
|--------|------------|----------|
| [Plug.Builder HexDocs](https://hexdocs.pm/plug/Plug.Builder.html) | HIGH | Plug halt semantics, init/call pattern |
| [Plug.Conn HexDocs](https://hexdocs.pm/plug/Plug.Conn.html) | HIGH | assigns pattern, halt flag design |
| [Exq.Middleware.Pipeline HexDocs](https://hexdocs.pm/exq/Exq.Middleware.Pipeline.html) | HIGH | assigns map, halt vs terminate semantics |
| [LlmGuard GitHub](https://github.com/North-Shore-AI/LlmGuard) | MEDIUM | Elixir AI guardrails detector chain pattern |
| [Elixir Behaviours — Elixir School](https://elixirschool.com/en/lessons/advanced/behaviours) | HIGH | @behaviour vs protocol selection |
| [Writing extensible Elixir with Behaviours](https://www.djm.org.uk/posts/writing-extensible-elixir-with-behaviours-adapters-pluggable-backends/) | HIGH | @callback contract for extensible modules |
| [Enum.reduce_while — Elixir docs](https://hexdocs.pm/elixir/Enum.html#reduce_while/3) | HIGH | Halt-on-first semantics executor |
| Existing `PhoenixAI.Pipeline.run/3` (codebase) | HIGH | Consistent railway pattern precedent |
| Existing `PhoenixAI.Agent.handle_call/3` (codebase) | HIGH | Exact integration point identified |

---

*Architecture research for: PhoenixAI v0.3.0 Guardrails Middleware-Chain Policy System*
*Researched: 2026-04-04*
