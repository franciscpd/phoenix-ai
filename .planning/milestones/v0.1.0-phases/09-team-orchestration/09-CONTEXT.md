# Phase 9: Team Orchestration - Context

**Gathered:** 2026-03-31
**Status:** Ready for planning

<domain>
## Phase Boundary

Parallel fan-out/fan-in execution where multiple agents (functions) run concurrently via `Task.async_stream`, with configurable `max_concurrency`, and results are merged by a caller-supplied function. Includes both a Macro DSL (`use PhoenixAI.Team`) for reusable named teams and a direct `Team.run/3` for ad-hoc usage. Team is agnostic to what each agent function does — they can call `AI.chat/2`, `Agent.prompt/2`, external APIs, or anything.

Team is **only parallel** (fan-out/fan-in). Sequential execution is handled by Pipeline (Phase 8). These are complementary — consumers can compose them: a Pipeline step can invoke a Team, and a Team agent can invoke a Pipeline.

**Not in scope:** Sequential execution (Phase 8), routing/coordination logic, agent lifecycle management, streaming integration, retry/backoff per agent.

</domain>

<decisions>
## Implementation Decisions

### Agent Specs (Fan-out)
- **D-01:** Agent specs are zero-arity anonymous functions: `fn -> {:ok, result} | {:error, reason} end`. Consistent with Pipeline steps (Phase 8) — functions as the unit of composition. Idiomatic Elixir pattern for `Task.async_stream`.
- **D-02:** No coupling to Agent GenServer. Specs can call `AI.chat/2`, `Agent.prompt/2`, HTTP APIs, or any code. Team does not know or care what happens inside a spec.
- **D-03:** Zero-arity (no input argument) because parallel agents are independent — they don't share input like Pipeline steps do.

### Merge Function (Fan-in)
- **D-04:** Merge function receives a list of ALL results as `[{:ok, term()} | {:error, term()}]` tuples. Every agent's result is included, including failures. Maximum transparency — nothing is hidden from the caller.
- **D-05:** Results are in deterministic order matching the input spec order (ORCH-06 requirement). `Task.async_stream` with `ordered: true` guarantees this.
- **D-06:** The merge function's return value becomes Team's return value. Team wraps it: `{:ok, merge_fn.(results)}`. If merge itself raises, the exception propagates (let it crash).

### Public API — Dual Mode
- **D-07:** **Ad-hoc mode:** `PhoenixAI.Team.run(specs, merge_fn, opts)` where `specs` is a list of zero-arity functions. Returns `{:ok, merged_result}`.
- **D-08:** **DSL mode:** `use PhoenixAI.Team` in a module with `agent :name do ... end` and `merge do ... end` macros. Generates `agents/0`, `agent_names/0`, `merge_fn/0`, and `run/0`/`run/1` on the consumer module. Consistent with Pipeline DSL pattern (Phase 8).
- **D-09:** The DSL compiles down to `Team.run/3` internally — same execution engine.
- **D-10:** Default opts: `max_concurrency: 5` (ORCH-05), `timeout: :infinity` (per-task timeout in `Task.async_stream`), `ordered: true`.

### Failure Handling
- **D-11:** Team ALWAYS waits for all agents to complete (success or failure). No fail-fast. All results are collected and passed to the merge function.
- **D-12:** A crashed/raised agent produces `{:error, {:task_failed, reason}}` in the results list. The Task exit is caught by `Task.async_stream`'s built-in error handling — it does not crash the caller.
- **D-13:** A timed-out agent (per `timeout` opt) produces `{:error, :timeout}` or `{:exit, :timeout}` depending on `Task.async_stream` behavior.
- **D-14:** If ALL agents fail, merge still receives all `{:error, _}` tuples. It's the merge function's responsibility to decide what to return. Team never short-circuits.

### Claude's Discretion
- Internal implementation details of `Task.async_stream` wrapper
- Whether `__using__` macro for Team reuses any code from Pipeline's macro
- How merge macro stores and retrieves the merge function in DSL mode
- Test strategy: Mox vs inline functions for concurrent test scenarios
- Whether `on_timeout: :kill_task` is the default for `Task.async_stream`

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Prior Phase Context
- `.planning/phases/08-pipeline-orchestration/08-CONTEXT.md` — D-01/D-08: Pipeline DSL pattern (step/2 macro, __before_compile__), D-04: term-free data flow, D-07: Pipeline.run/2 ad-hoc mode
- `.planning/phases/04-agent-genserver/04-CONTEXT.md` — D-01/D-02: Agent API (start_link, prompt/2), D-09: Task.async inside GenServer, D-13: process isolation

### Existing Code
- `lib/phoenix_ai/pipeline.ex` — Pipeline module with DSL macros — architectural pattern to follow for Team DSL
- `lib/phoenix_ai/tool_loop.ex` — Pure functional module pattern
- `lib/ai.ex` — `AI.chat/2` dispatch — what agent specs will commonly call
- `lib/phoenix_ai/agent.ex` — `Agent.prompt/2` — what agent specs may call

### Elixir Patterns
- `Task.async_stream/3` — core primitive for bounded parallel execution with `max_concurrency` and `ordered` options
- `Task.Supervisor` — for supervised task execution (may be relevant for production use)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `PhoenixAI.Pipeline` — DSL macro pattern (`__using__`, `step/2`, `__before_compile__`) to replicate for Team's `agent/2` macro
- `Pipeline.run/2` via `Enum.reduce_while` — sequential pattern. Team uses `Task.async_stream` instead.
- `AI.chat/2` — primary function agent specs will call

### Established Patterns
- Pure functional modules for orchestration (ToolLoop, Pipeline)
- DSL via `use Module` + macros + `@before_compile` (Pipeline precedent)
- `{:ok, result} | {:error, reason}` tuples everywhere
- Opts-driven API with keyword lists and sensible defaults

### Integration Points
- `PhoenixAI.Team` — new module under `lib/phoenix_ai/team.ex`
- No integration needed with Pipeline — Team is standalone
- Consumers can compose: `Pipeline.run([..., fn _ -> Team.run(specs, merge) end, ...], input)`

</code_context>

<specifics>
## Specific Ideas

- Team's DSL (`use PhoenixAI.Team` + `agent :name do` + `merge do`) mirrors Pipeline's DSL pattern for consistency across the library
- Zero-arity specs (vs Pipeline's unary steps) reflects that parallel agents are independent — they don't chain input/output
- Merge receiving ALL results (including errors) follows Elixir's transparency philosophy — the caller always knows what happened
- `max_concurrency: 5` as default is conservative — prevents overwhelming API rate limits while still enabling meaningful parallelism
- The fan-out/fan-in + Pipeline composition enables complex workflows: search in parallel → merge → summarize sequentially

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 09-team-orchestration*
*Context gathered: 2026-03-31*
