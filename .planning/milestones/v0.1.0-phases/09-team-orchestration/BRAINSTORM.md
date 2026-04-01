# Phase 9: Team Orchestration — Design Spec

**Date:** 2026-03-31
**Phase:** 09-team-orchestration
**Requirements:** ORCH-04, ORCH-05, ORCH-06

## Summary

Parallel fan-out/fan-in execution where multiple agent specs (zero-arity functions) run concurrently via `Task.async_stream`, with configurable `max_concurrency` (default 5), and results are merged by a caller-supplied function. Dual API: Macro DSL (`use PhoenixAI.Team`) for reusable named teams and `Team.run/3` for ad-hoc usage.

## Architecture

### Single Module

**File:** `lib/phoenix_ai/team.ex`
**Module:** `PhoenixAI.Team`

One module contains both the execution logic (`run/3`) and the DSL macros (`agent/2`, `merge/1`, `__using__/1`, `__before_compile__/1`). Follows the same pattern as `PhoenixAI.Pipeline`.

### Run Loop — `Task.async_stream/3`

```elixir
@type agent_spec :: (() -> {:ok, term()} | {:error, term()} | term())
@type merge_fn :: ([{:ok, term()} | {:error, term()}] -> term())

@spec run([agent_spec()], merge_fn(), keyword()) :: {:ok, term()}
def run(specs, merge_fn, opts \\ []) do
  max_concurrency = Keyword.get(opts, :max_concurrency, 5)
  timeout = Keyword.get(opts, :timeout, :infinity)
  ordered = Keyword.get(opts, :ordered, true)

  results =
    specs
    |> Task.async_stream(fn spec -> safe_execute(spec) end,
      max_concurrency: max_concurrency,
      timeout: timeout,
      on_timeout: :kill_task,
      ordered: ordered
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, reason} -> {:error, {:task_failed, reason}}
    end)

  {:ok, merge_fn.(results)}
end

defp safe_execute(spec) do
  spec.()
rescue
  e -> {:error, {:task_failed, Exception.message(e)}}
end
```

### Types

```elixir
@type agent_spec :: (() -> {:ok, term()} | {:error, term()} | term())
@type merge_fn :: ([{:ok, term()} | {:error, term()}] -> term())
```

## Agent Spec Definition

Agent specs are zero-arity anonymous functions: `fn -> {:ok, result} | {:error, reason} end`.

- No coupling to Agent GenServer — specs can call anything
- Zero-arity (no input) because parallel agents are independent
- Consistent with Pipeline steps (functions as composition unit)

## Data Contract

- Each spec returns `{:ok, term()}` or `{:error, term()}`
- Non-tuple returns from specs are passed through as-is (no auto-wrap — specs should return tuples)
- Crashed specs produce `{:error, {:task_failed, message}}` via `safe_execute/1`
- Timed-out/killed tasks produce `{:error, {:task_failed, reason}}` via `Task.async_stream` exit handling
- Merge function receives a list of ALL results: `[{:ok, term()} | {:error, term()}]`
- Merge function's return value is wrapped: `{:ok, merge_fn.(results)}`

## Public API

### Ad-hoc Mode

```elixir
{:ok, merged} = PhoenixAI.Team.run(
  [spec1, spec2, spec3],
  fn results -> merge(results) end,
  max_concurrency: 5,
  timeout: 30_000,
  ordered: true
)
```

- `specs` — list of zero-arity functions
- `merge_fn` — function receiving list of result tuples
- `opts` — keyword list: `:max_concurrency` (default 5), `:timeout` (default `:infinity`), `:ordered` (default `true`)
- Returns `{:ok, merged_result}`

### DSL Mode

```elixir
defmodule MyApp.ResearchTeam do
  use PhoenixAI.Team

  agent :researcher do
    fn -> AI.chat([msg("Pesquise X")], provider: :openai) end
  end

  agent :analyst do
    fn -> AI.chat([msg("Analise Y")], provider: :anthropic) end
  end

  merge do
    fn results ->
      results
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.map(fn {:ok, r} -> r.content end)
      |> Enum.join("\n")
    end
  end
end

MyApp.ResearchTeam.run(max_concurrency: 3)
```

### DSL Macro Implementation

```elixir
defmacro __using__(_opts) do
  quote do
    import PhoenixAI.Team, only: [agent: 2, merge: 1]
    Module.register_attribute(__MODULE__, :team_agents, accumulate: true)
    Module.register_attribute(__MODULE__, :team_merge_fn, accumulate: false)
    @before_compile PhoenixAI.Team
  end
end

defmacro agent(name, do: block) do
  escaped_block = Macro.escape(block)
  quote do
    @team_agents {unquote(name), unquote(escaped_block)}
  end
end

defmacro merge(do: block) do
  escaped_block = Macro.escape(block)
  quote do
    @team_merge_fn unquote(escaped_block)
  end
end

defmacro __before_compile__(env) do
  agents = Module.get_attribute(env.module, :team_agents) |> Enum.reverse()
  merge_fn_ast = Module.get_attribute(env.module, :team_merge_fn)

  agent_funs = Enum.map(agents, fn {_name, fun} -> fun end)
  agent_names = Enum.map(agents, fn {name, _fun} -> name end)

  quote do
    def agents, do: unquote(agent_funs)
    def agent_names, do: unquote(agent_names)
    def merge_fn, do: unquote(merge_fn_ast)

    def run(opts \\ []) do
      PhoenixAI.Team.run(agents(), merge_fn(), opts)
    end
  end
end
```

**Generated functions on consumer module:**
- `agents/0` — list of agent spec functions in definition order
- `agent_names/0` — list of agent name atoms (e.g., `[:researcher, :analyst]`)
- `merge_fn/0` — the merge function
- `run/0`, `run/1` — shortcut to `Team.run(agents(), merge_fn(), opts)`

## Error Handling

### Spec Crashes — `safe_execute/1`
- Exceptions inside specs are rescued and transformed to `{:error, {:task_failed, message}}`
- Different from Pipeline (which propagates exceptions) because one crash should not prevent collecting other parallel results

### Task.async_stream Exits
- `{:exit, reason}` from `Task.async_stream` (timeout, killed) → `{:error, {:task_failed, reason}}`
- `on_timeout: :kill_task` ensures cleanup of tasks exceeding timeout

### Merge Function Crash
- If `merge_fn` raises, exception propagates to the caller (let it crash)
- Team does not rescue the merge function

### Edge Cases
- **Empty specs list:** `Team.run([], merge_fn)` → `{:ok, merge_fn.([])}`  — merge receives empty list
- **Non-function spec:** `spec.()` raises `BadFunctionError` → caught by rescue → `{:error, {:task_failed, "..."}}`

## Testing Strategy

### `test/phoenix_ai/team_test.exs` — run/3 tests
- 3 specs all returning `{:ok, _}` → merge receives 3 results, returns `{:ok, merged}`
- 1 of 3 specs returns `{:error, _}` → merge receives 2 ok + 1 error, Team returns `{:ok, merged}`
- Spec that raises exception → captured as `{:error, {:task_failed, msg}}`, does not crash caller
- Empty specs list → merge receives `[]`
- `max_concurrency: 1` → executes sequentially (proves option works)
- Deterministic ordering → results in same order as specs regardless of completion order

### `test/phoenix_ai/team_dsl_test.exs` — macro DSL tests
- Module with `use PhoenixAI.Team` + 2 agents + merge → `run/0` works
- `agents/0` returns list of functions
- `agent_names/0` returns `[:researcher, :analyst]`
- DSL with failing spec → merge receives error, Team returns `{:ok, merged}`
- `run/1` with opts → `max_concurrency` passed to `Task.async_stream`

### No mocks, no network
All specs are pure functions (return fixed values, use `Process.sleep` for concurrency timing tests). No `AI.chat/2` calls.

## Not In Scope
- Sequential execution (Phase 8: Pipeline)
- Routing/coordination logic
- Agent lifecycle management
- Streaming integration
- Retry/backoff per agent
- Telemetry events (Phase 10)
