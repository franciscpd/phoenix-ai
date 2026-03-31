# Phase 8: Pipeline Orchestration — Design Spec

**Date:** 2026-03-31
**Phase:** 08-pipeline-orchestration
**Requirements:** ORCH-01, ORCH-02, ORCH-03

## Summary

Sequential railway pipeline where steps are anonymous functions, each output feeds the next input (term-free like Ecto.Multi), and the pipeline halts on first `{:error, reason}`. Dual API: Macro DSL (`use PhoenixAI.Pipeline`) for reusable named pipelines and `Pipeline.run/2` for ad-hoc usage.

## Architecture

### Single Module

**File:** `lib/phoenix_ai/pipeline.ex`
**Module:** `PhoenixAI.Pipeline`

One module contains both the execution logic (`run/2`, `run/3`) and the DSL macro (`step/2`, `__using__/1`, `__before_compile__/1`). Follows the same pattern as `PhoenixAI.ToolLoop` — a pure functional module that does one thing well.

### Run Loop — `Enum.reduce_while/3`

```elixir
@spec run([step()], term(), keyword()) :: {:ok, term()} | {:error, term()}
def run(steps, input, opts \\ []) do
  Enum.reduce_while(steps, {:ok, input}, fn step, {:ok, value} ->
    case normalize_return(step.(value)) do
      {:ok, _} = ok -> {:cont, ok}
      {:error, _} = err -> {:halt, err}
    end
  end)
end

@spec normalize_return(term()) :: {:ok, term()} | {:error, term()}
defp normalize_return({:ok, _} = ok), do: ok
defp normalize_return({:error, _} = err), do: err
defp normalize_return(other), do: {:ok, other}
```

### Types

```elixir
@type step() :: (term() -> {:ok, term()} | {:error, term()} | term())
```

## Step Definition

Steps are anonymous functions: `fn input -> {:ok, result} | {:error, reason} end`.

- No behaviour required — zero ceremony
- Steps can call anything: `AI.chat/2`, `Agent.prompt/2`, external APIs, pure transformations
- Pipeline is agnostic to step internals

## Data Contract

Term-free data flow inspired by Ecto.Multi:

- Each step returns `{:ok, any_term}` or `{:error, reason}`
- Next step receives the unwrapped value from `{:ok, value}`
- Initial input is any term (string, map, struct)
- Non-tuple returns are auto-wrapped in `{:ok, value}` (pragmatic convenience)

## Public API

### Ad-hoc Mode

```elixir
PhoenixAI.Pipeline.run(steps, initial_input)
PhoenixAI.Pipeline.run(steps, initial_input, name: "search-pipeline")
```

- `steps` — list of functions
- `initial_input` — any term
- `opts` — keyword list (`:name` for future telemetry in Phase 10)
- Returns `{:ok, final_result}` or `{:error, reason}`

### DSL Mode

```elixir
defmodule MyApp.SearchPipeline do
  use PhoenixAI.Pipeline

  step :search do
    fn query ->
      AI.chat([%Message{role: :user, content: query}], provider: :openai)
    end
  end

  step :format do
    fn %Response{content: text} -> String.upcase(text) end
  end
end

MyApp.SearchPipeline.run("Pesquise sobre Elixir")
```

### DSL Macro Implementation

```elixir
defmacro __using__(_opts) do
  quote do
    import PhoenixAI.Pipeline, only: [step: 2]
    Module.register_attribute(__MODULE__, :pipeline_steps, accumulate: true)
    @before_compile PhoenixAI.Pipeline
  end
end

defmacro step(name, do: block) do
  quote do
    @pipeline_steps {unquote(name), unquote(block)}
  end
end

defmacro __before_compile__(env) do
  steps = Module.get_attribute(env.module, :pipeline_steps) |> Enum.reverse()

  quote do
    def steps do
      unquote(Enum.map(steps, fn {_name, fun} -> fun end))
    end

    def step_names do
      unquote(Enum.map(steps, fn {name, _fun} -> name end))
    end

    def run(input, opts \\ []) do
      PhoenixAI.Pipeline.run(steps(), input, opts)
    end
  end
end
```

**Generated functions on consumer module:**
- `steps/0` — list of step functions in definition order
- `step_names/0` — list of step name atoms (e.g., `[:search, :format]`)
- `run/1`, `run/2` — shortcut to `Pipeline.run(steps(), input, opts)`

## Error Handling

### Railway Semantics
- `{:ok, value}` → unwrap, pass to next step
- `{:error, reason}` → halt immediately, return `{:error, reason}`, no subsequent steps execute

### Exceptions — Let It Crash
- Pipeline does NOT rescue exceptions
- If a step raises, exception propagates to the caller
- Consumer handles via supervision tree (OTP philosophy)
- Consistent with ToolLoop behavior

### Edge Cases
- **Empty steps list:** `Pipeline.run([], input)` → `{:ok, input}` (noop)
- **Non-tuple return:** Auto-wrapped in `{:ok, value}` via `normalize_return/1`
- **Non-function step:** `step.(value)` raises `BadFunctionError` naturally (no pre-validation)

## Testing Strategy

### `test/phoenix_ai/pipeline_test.exs` — run/2 tests
- 3 steps all returning `{:ok, _}` → executes all, returns final result
- Step 2 returns `{:error, _}` → step 3 never executes, returns error
- Empty steps list → returns `{:ok, input}`
- Step returns raw value (non-tuple) → auto-wrapped in `{:ok, value}`
- Step raises exception → propagates without rescue

### `test/phoenix_ai/pipeline_dsl_test.exs` — macro DSL tests
- Module with `use PhoenixAI.Pipeline` + 2 steps → `run/1` works
- `steps/0` returns list of functions in correct order
- `step_names/0` returns `[:step1, :step2]`
- DSL pipeline with error in middle step → halts correctly

### No mocks, no network
All tests use pure steps (string/map transformations). No `AI.chat/2` calls. Pipeline is agnostic.

## Not In Scope
- Parallel execution (Phase 9: Team Orchestration)
- Streaming integration
- Agent lifecycle management
- Step retry/backoff
- Per-step timeout
- Telemetry events (Phase 10)
