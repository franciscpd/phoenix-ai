# Pipeline Orchestration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement sequential railway pipeline with `Pipeline.run/2` (ad-hoc) and `use PhoenixAI.Pipeline` DSL (reusable), where each step output feeds the next input and the pipeline halts on first error.

**Architecture:** Single module `PhoenixAI.Pipeline` containing both execution logic (`run/2`, `run/3` via `Enum.reduce_while/3`) and DSL macros (`step/2`, `__using__/1`, `__before_compile__/1`). Steps are anonymous functions returning `{:ok, term()} | {:error, term()} | term()` (raw values auto-wrapped). Follows the `ToolLoop` pattern — pure functional, no GenServer.

**Tech Stack:** Elixir, ExUnit, no new dependencies

**Requirements:** ORCH-01, ORCH-02, ORCH-03

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `lib/phoenix_ai/pipeline.ex` | Create | `PhoenixAI.Pipeline` — `run/2`, `run/3`, `normalize_return/1`, DSL macros |
| `test/phoenix_ai/pipeline_test.exs` | Create | Tests for `Pipeline.run/2` — happy path, error halt, empty steps, auto-wrap, exception propagation |
| `test/phoenix_ai/pipeline_dsl_test.exs` | Create | Tests for DSL macro — `use PhoenixAI.Pipeline`, `step/2`, generated `run/1`, `steps/0`, `step_names/0` |

---

### Task 1: Pipeline.run/2 — Happy Path (3-step pipeline)

**Files:**
- Create: `test/phoenix_ai/pipeline_test.exs`
- Create: `lib/phoenix_ai/pipeline.ex`

- [ ] **Step 1: Write the failing test**

```elixir
# test/phoenix_ai/pipeline_test.exs
defmodule PhoenixAI.PipelineTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Pipeline

  describe "run/2" do
    test "executes all steps sequentially, passing output as next input" do
      steps = [
        fn input -> {:ok, input <> " step1"} end,
        fn input -> {:ok, input <> " step2"} end,
        fn input -> {:ok, input <> " step3"} end
      ]

      assert {:ok, "hello step1 step2 step3"} = Pipeline.run(steps, "hello")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/phoenix_ai/pipeline_test.exs --trace`
Expected: FAIL — `PhoenixAI.Pipeline` module does not exist

- [ ] **Step 3: Write minimal implementation**

```elixir
# lib/phoenix_ai/pipeline.ex
defmodule PhoenixAI.Pipeline do
  @moduledoc """
  Sequential railway pipeline.

  Steps execute in order. Each step receives the previous step's unwrapped
  `{:ok, value}` result. The pipeline halts on the first `{:error, reason}`.

  ## Ad-hoc usage

      Pipeline.run([
        fn query -> AI.chat([msg(query)], provider: :openai) end,
        fn %Response{content: text} -> String.upcase(text) end
      ], "Hello")

  ## DSL usage

      defmodule MyPipeline do
        use PhoenixAI.Pipeline

        step :search do
          fn query -> AI.chat([msg(query)], provider: :openai) end
        end
      end

      MyPipeline.run("Hello")
  """

  @type step :: (term() -> {:ok, term()} | {:error, term()} | term())

  @doc """
  Executes a list of step functions sequentially.

  Each step receives the unwrapped value from the previous step's `{:ok, value}`.
  Halts on first `{:error, reason}`. Raw (non-tuple) returns are auto-wrapped
  in `{:ok, value}`.
  """
  @spec run([step()], term(), keyword()) :: {:ok, term()} | {:error, term()}
  def run(steps, input, opts \\ [])

  def run([], input, _opts), do: {:ok, input}

  def run(steps, input, _opts) do
    Enum.reduce_while(steps, {:ok, input}, fn step, {:ok, value} ->
      case normalize_return(step.(value)) do
        {:ok, _} = ok -> {:cont, ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  @doc false
  defp normalize_return({:ok, _} = ok), do: ok
  defp normalize_return({:error, _} = err), do: err
  defp normalize_return(other), do: {:ok, other}
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/phoenix_ai/pipeline_test.exs --trace`
Expected: 1 test, 0 failures

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_ai/pipeline.ex test/phoenix_ai/pipeline_test.exs
git commit -m "feat(08): add Pipeline.run/2 with sequential step execution"
```

---

### Task 2: Pipeline.run/2 — Error Halting (ORCH-03)

**Files:**
- Modify: `test/phoenix_ai/pipeline_test.exs`

- [ ] **Step 1: Write the failing test**

Add to the `describe "run/2"` block in `test/phoenix_ai/pipeline_test.exs`:

```elixir
    test "halts on first {:error, _} and does not execute subsequent steps" do
      test_pid = self()

      steps = [
        fn input -> {:ok, input <> " step1"} end,
        fn _input -> {:error, :something_failed} end,
        fn input ->
          send(test_pid, :step3_executed)
          {:ok, input <> " step3"}
        end
      ]

      assert {:error, :something_failed} = Pipeline.run(steps, "hello")
      refute_received :step3_executed
    end
```

- [ ] **Step 2: Run test to verify it passes**

Run: `mix test test/phoenix_ai/pipeline_test.exs --trace`
Expected: 2 tests, 0 failures (this should already pass with the `Enum.reduce_while` implementation)

- [ ] **Step 3: Commit**

```bash
git add test/phoenix_ai/pipeline_test.exs
git commit -m "test(08): add error halting test for Pipeline.run/2"
```

---

### Task 3: Pipeline.run/2 — Edge Cases (empty list, auto-wrap, exception)

**Files:**
- Modify: `test/phoenix_ai/pipeline_test.exs`

- [ ] **Step 1: Write the empty steps test**

Add to the `describe "run/2"` block:

```elixir
    test "empty steps list returns {:ok, input}" do
      assert {:ok, "unchanged"} = Pipeline.run([], "unchanged")
    end
```

- [ ] **Step 2: Run test to verify it passes**

Run: `mix test test/phoenix_ai/pipeline_test.exs --trace`
Expected: 3 tests, 0 failures (already handled by the `run([], input, _opts)` clause)

- [ ] **Step 3: Write the auto-wrap test**

Add to the `describe "run/2"` block:

```elixir
    test "non-tuple return is auto-wrapped in {:ok, value}" do
      steps = [
        fn input -> String.upcase(input) end,
        fn input -> {:ok, input <> "!"} end
      ]

      assert {:ok, "HELLO!"} = Pipeline.run(steps, "hello")
    end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/phoenix_ai/pipeline_test.exs --trace`
Expected: 4 tests, 0 failures (handled by `normalize_return/1`)

- [ ] **Step 5: Write the exception propagation test**

Add to the `describe "run/2"` block:

```elixir
    test "step that raises propagates the exception" do
      steps = [
        fn _input -> raise "boom" end
      ]

      assert_raise RuntimeError, "boom", fn ->
        Pipeline.run(steps, "hello")
      end
    end
```

- [ ] **Step 6: Run test to verify it passes**

Run: `mix test test/phoenix_ai/pipeline_test.exs --trace`
Expected: 5 tests, 0 failures

- [ ] **Step 7: Commit**

```bash
git add test/phoenix_ai/pipeline_test.exs
git commit -m "test(08): add edge case tests — empty steps, auto-wrap, exception propagation"
```

---

### Task 4: DSL Macro — Basic `use PhoenixAI.Pipeline` + `step/2`

**Files:**
- Modify: `lib/phoenix_ai/pipeline.ex`
- Create: `test/phoenix_ai/pipeline_dsl_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
# test/phoenix_ai/pipeline_dsl_test.exs
defmodule PhoenixAI.PipelineDSLTest do
  use ExUnit.Case, async: true

  defmodule TwoStepPipeline do
    use PhoenixAI.Pipeline

    step :upcase do
      fn input -> {:ok, String.upcase(input)} end
    end

    step :exclaim do
      fn input -> {:ok, input <> "!"} end
    end
  end

  describe "DSL module" do
    test "run/1 executes steps sequentially" do
      assert {:ok, "HELLO!"} = TwoStepPipeline.run("hello")
    end

    test "steps/0 returns list of functions" do
      steps = TwoStepPipeline.steps()
      assert length(steps) == 2
      assert is_function(hd(steps), 1)
    end

    test "step_names/0 returns ordered atom list" do
      assert [:upcase, :exclaim] = TwoStepPipeline.step_names()
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/phoenix_ai/pipeline_dsl_test.exs --trace`
Expected: FAIL — `__using__/1` macro not defined

- [ ] **Step 3: Add DSL macros to Pipeline module**

Add the following to `lib/phoenix_ai/pipeline.ex` inside the module, before `run/3`:

```elixir
  defmacro __using__(_opts) do
    quote do
      import PhoenixAI.Pipeline, only: [step: 2]
      Module.register_attribute(__MODULE__, :pipeline_steps, accumulate: true)
      @before_compile PhoenixAI.Pipeline
    end
  end

  @doc """
  Defines a named step in a pipeline module.

  The block must return a function `fn input -> {:ok, result} | {:error, reason} | term() end`.
  """
  defmacro step(name, do: block) do
    quote do
      @pipeline_steps {unquote(name), unquote(block)}
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    steps = Module.get_attribute(env.module, :pipeline_steps) |> Enum.reverse()
    step_funs = Enum.map(steps, fn {_name, fun} -> fun end)
    step_names = Enum.map(steps, fn {name, _fun} -> name end)

    quote do
      @doc "Returns the list of step functions in definition order."
      def steps, do: unquote(step_funs)

      @doc "Returns the list of step name atoms in definition order."
      def step_names, do: unquote(step_names)

      @doc "Runs the pipeline with the given input."
      def run(input, opts \\ []) do
        PhoenixAI.Pipeline.run(steps(), input, opts)
      end
    end
  end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/phoenix_ai/pipeline_dsl_test.exs --trace`
Expected: 3 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_ai/pipeline.ex test/phoenix_ai/pipeline_dsl_test.exs
git commit -m "feat(08): add Pipeline DSL macro — use PhoenixAI.Pipeline + step/2"
```

---

### Task 5: DSL — Error Halting + Auto-wrap in DSL Pipeline

**Files:**
- Modify: `test/phoenix_ai/pipeline_dsl_test.exs`

- [ ] **Step 1: Write the error halting test**

Add to `test/phoenix_ai/pipeline_dsl_test.exs`:

```elixir
  defmodule ErrorPipeline do
    use PhoenixAI.Pipeline

    step :first do
      fn input -> {:ok, input <> " first"} end
    end

    step :fail do
      fn _input -> {:error, :broken} end
    end

    step :never do
      fn input -> {:ok, input <> " never"} end
    end
  end

  describe "DSL error handling" do
    test "halts on first error, skips remaining steps" do
      assert {:error, :broken} = ErrorPipeline.run("hello")
    end
  end
```

- [ ] **Step 2: Write the auto-wrap test**

Add to `test/phoenix_ai/pipeline_dsl_test.exs`:

```elixir
  defmodule AutoWrapPipeline do
    use PhoenixAI.Pipeline

    step :raw_return do
      fn input -> String.upcase(input) end
    end

    step :add_bang do
      fn input -> {:ok, input <> "!"} end
    end
  end

  describe "DSL auto-wrap" do
    test "non-tuple return from DSL step is auto-wrapped" do
      assert {:ok, "HELLO!"} = AutoWrapPipeline.run("hello")
    end
  end
```

- [ ] **Step 3: Run all tests to verify they pass**

Run: `mix test test/phoenix_ai/pipeline_dsl_test.exs --trace`
Expected: 5 tests, 0 failures

- [ ] **Step 4: Commit**

```bash
git add test/phoenix_ai/pipeline_dsl_test.exs
git commit -m "test(08): add DSL error halting and auto-wrap tests"
```

---

### Task 6: Run Full Test Suite + Format Check

**Files:**
- No file changes expected

- [ ] **Step 1: Run the full test suite**

Run: `mix test --trace`
Expected: All existing tests still pass, plus the new 10 Pipeline tests (5 in pipeline_test, 5 in pipeline_dsl_test)

- [ ] **Step 2: Run formatter**

Run: `mix format --check-formatted`
Expected: No formatting issues

- [ ] **Step 3: Run Credo**

Run: `mix credo --strict`
Expected: No new issues in `lib/phoenix_ai/pipeline.ex` or test files

- [ ] **Step 4: Fix any issues found**

If formatter or Credo report issues, fix them in the relevant files.

- [ ] **Step 5: Commit fixes if any**

```bash
git add -A
git commit -m "style(08): fix formatting/credo issues in Pipeline module"
```

(Skip this step if no issues were found)

---

## Verification

After all tasks complete, these success criteria from the roadmap must be TRUE:

1. **ORCH-01:** `PhoenixAI.Pipeline.run(steps, initial_input)` executes each step in order, passing the previous `{:ok, result}` value as input to the next step
2. **ORCH-02:** Step output becomes next step input (term-free, unwrapped from `{:ok, value}`)
3. **ORCH-03:** If any step returns `{:error, reason}`, the pipeline stops immediately and returns that error — no subsequent steps execute

Run: `mix test test/phoenix_ai/pipeline_test.exs test/phoenix_ai/pipeline_dsl_test.exs --trace`
Expected: 10 tests, 0 failures
