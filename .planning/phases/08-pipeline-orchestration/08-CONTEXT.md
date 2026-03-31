# Phase 8: Pipeline Orchestration - Context

**Gathered:** 2026-03-31
**Status:** Ready for planning

<domain>
## Phase Boundary

Sequential pipeline execution where steps are functions, each output feeds the next input (term-free like Ecto.Multi), and the pipeline halts on the first `{:error, reason}`. Includes both a Macro DSL (`use PhoenixAI.Pipeline`) for reusable named pipelines and a direct `Pipeline.run/2` for ad-hoc usage. Pipeline is agnostic to what steps do — they can call `AI.chat/2`, `Agent.prompt/2`, external APIs, or pure transformations.

**Not in scope:** Parallel execution (Phase 9), streaming integration, Agent lifecycle management, step retry/backoff, step timeout per-step.

</domain>

<decisions>
## Implementation Decisions

### Step Definition
- **D-01:** Steps are anonymous functions: `fn input -> {:ok, result} | {:error, reason} end`. This follows the idiomatic Elixir pattern of functional composition (like Plug, Enum.reduce).
- **D-02:** No behaviour required for steps. Steps are plain functions — zero ceremony, maximum flexibility.
- **D-03:** Steps can call anything inside: `AI.chat/2`, `Agent.prompt/2`, external HTTP calls, pure data transformations. Pipeline does not know or care what happens inside a step.

### Input/Output Contract
- **D-04:** Term-free data flow, inspired by Ecto.Multi. Each step returns `{:ok, any_term}` or `{:error, reason}`. The next step receives the unwrapped value from `{:ok, value}`.
- **D-05:** The `@spec` for steps is `(term() -> {:ok, term()} | {:error, term()})`. The contract is on the tuple shape, not the internal type.
- **D-06:** The initial input to `Pipeline.run/2` is any term — string, map, struct, whatever the first step expects. No automatic conversion.

### Public API — Dual Mode
- **D-07:** **Ad-hoc mode:** `PhoenixAI.Pipeline.run(steps, initial_input)` where `steps` is a list of functions. Direct, no module needed. Returns `{:ok, final_result}` or `{:error, reason}`.
- **D-08:** **DSL mode:** `use PhoenixAI.Pipeline` in a module with `step :name do ... end` macro. Generates a `run/1` function on the module. For reusable, named pipelines.
- **D-09:** The DSL compiles down to `Pipeline.run/2` internally — same execution engine, different definition ergonomics.
- **D-10:** Optional third argument for opts: `Pipeline.run(steps, input, name: "search-pipeline")` — useful for telemetry/logging in Phase 10.

### Railway Semantics
- **D-11:** On `{:ok, value}` — unwrap value, pass to next step.
- **D-12:** On `{:error, reason}` — halt immediately, return `{:error, reason}`. No subsequent steps execute. This is ORCH-03.
- **D-13:** If a step raises an exception, it propagates uncaught (Elixir "let it crash" philosophy). Pipeline does not rescue exceptions — that's the consumer's responsibility via supervision.

### Agent Integration
- **D-14:** No special Agent integration. Pipeline is agnostic — steps call whatever they want. If a consumer wants to use an Agent, they call `Agent.prompt/2` inside a step function. Pipeline has zero coupling to Agent.

### Claude's Discretion
- Internal implementation of the `__using__` macro and `step` macro
- Whether to use `Enum.reduce_while` or manual recursion for the run loop
- Exact opts supported in `Pipeline.run/3` for v1 (name, etc.)
- Test strategy: inline functions vs test helper modules
- Whether DSL steps support options (e.g., `step :search, timeout: 5000 do`)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Prior Phase Context
- `.planning/phases/01-core-foundation/01-CONTEXT.md` — D-02: `AI` facade module, D-05: call-site opts pattern, D-09: Provider behaviour
- `.planning/phases/03-tool-calling/03-CONTEXT.md` — D-12/D-14: ToolLoop as pure functional module pattern (recursive, max iterations)
- `.planning/phases/04-agent-genserver/04-CONTEXT.md` — D-01/D-02: Agent API, D-17: Agent delegates to ToolLoop

### Existing Code
- `lib/phoenix_ai/tool_loop.ex` — Pure functional module with `run/4`, recursive loop — architectural pattern to follow
- `lib/ai.ex` — `AI.chat/2` and `AI.stream/2` dispatch — what steps will call
- `lib/phoenix_ai/agent.ex` — `Agent.prompt/2` — what steps may optionally call
- `lib/phoenix_ai/response.ex` — `%Response{}` struct — common return type from AI calls

### Elixir Patterns
- `Ecto.Multi` — term-free sequential operations with ok/error railway (inspiration for data contract)
- `Plug` — functional composition pipeline (inspiration for step-as-function pattern)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `PhoenixAI.ToolLoop` — pure functional module with recursive loop, same architectural pattern for Pipeline
- `AI.chat/2` — primary function steps will call for AI interactions
- `PhoenixAI.Response` — common struct returned by AI calls, will flow through pipeline steps naturally

### Established Patterns
- Pure functional modules (no GenServer) for orchestration logic (ToolLoop precedent)
- `{:ok, result} | {:error, reason}` tuples everywhere — Pipeline naturally extends this
- Opts-driven API with keyword lists (`run/3` with opts)
- No auto-starting processes — Pipeline is a pure module

### Integration Points
- `PhoenixAI.Pipeline` — new module under `lib/phoenix_ai/pipeline.ex`
- No integration needed with existing modules — Pipeline is standalone, steps call existing modules
- Future: Phase 10 telemetry will hook into Pipeline opts (`:name` for telemetry event metadata)

</code_context>

<specifics>
## Specific Ideas

- The DSL (`use PhoenixAI.Pipeline` + `step :name do`) is inspired by Broadway's declarative module pattern — familiar to Elixir developers
- `Pipeline.run/2` ad-hoc mode mirrors how `ToolLoop.run/4` works — a function you call, not a process you start
- Ecto.Multi's term-free approach was explicitly chosen over a fixed `%Response{}` type because pipeline steps aren't always AI calls — they can be pure transformations, API calls, or data formatting
- The railway halt-on-error behavior means consumers don't need explicit error handling between steps — the pipeline handles propagation

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 08-pipeline-orchestration*
*Context gathered: 2026-03-31*
