# Team Orchestration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement parallel fan-out/fan-in execution with `Team.run/3` (ad-hoc) and `use PhoenixAI.Team` DSL (reusable), where agent specs run concurrently via `Task.async_stream` and results are merged by a caller-supplied function.

**Architecture:** Single module `PhoenixAI.Team` containing execution logic (`run/3` via `Task.async_stream/3`, `safe_execute/1` for crash isolation) and DSL macros (`agent/2`, `merge/1`, `__using__/1`, `__before_compile__/1`). Agent specs are zero-arity functions. Merge receives all results as `[{:ok, _} | {:error, _}]`. Follows the `Pipeline` pattern.

**Tech Stack:** Elixir, ExUnit, no new dependencies

**Requirements:** ORCH-04, ORCH-05, ORCH-06

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `lib/phoenix_ai/team.ex` | Create | `PhoenixAI.Team` — `run/3`, `safe_execute/1`, DSL macros |
| `test/phoenix_ai/team_test.exs` | Create | Tests for `Team.run/3` — happy path, partial errors, crash isolation, empty specs, max_concurrency, ordering |
| `test/phoenix_ai/team_dsl_test.exs` | Create | Tests for DSL macro — `use PhoenixAI.Team`, `agent/2`, `merge/1`, generated functions |

---

### Task 1: Team.run/3 — Happy Path (3 specs, all succeed)

**Files:**
- Create: `test/phoenix_ai/team_test.exs`
- Create: `lib/phoenix_ai/team.ex`

- [ ] **Step 1: Write the failing test**

```elixir
# test/phoenix_ai/team_test.exs
defmodule PhoenixAI.TeamTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Team

  describe "run/3" do
    test "executes all specs in parallel and passes results to merge" do
      specs = [
        fn -> {:ok, "result_a"} end,
        fn -> {:ok, "result_b"} end,
        fn -> {:ok, "result_c"} end
      ]

      merge_fn = fn results ->
        results
        |> Enum.map(fn {:ok, val} -> val end)
        |> Enum.join(", ")
      end

      assert {:ok, "result_a, result_b, result_c"} = Team.run(specs, merge_fn)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/phoenix_ai/team_test.exs --trace`
Expected: FAIL — `PhoenixAI.Team` module does not exist

- [ ] **Step 3: Write minimal implementation**

```elixir
# lib/phoenix_ai/team.ex
defmodule PhoenixAI.Team do
  @moduledoc """
  Parallel fan-out/fan-in execution.

  Agent specs run concurrently via `Task.async_stream`. Results are collected
  and passed to a merge function. Crashed specs produce `{:error, {:task_failed, reason}}`
  instead of crashing the caller.

  ## Ad-hoc usage

      Team.run([
        fn -> AI.chat([msg("Search X")], provider: :openai) end,
        fn -> AI.chat([msg("Search Y")], provider: :anthropic) end
      ], fn results -> merge(results) end, max_concurrency: 5)

  ## DSL usage

      defmodule MyTeam do
        use PhoenixAI.Team

        agent :researcher do
          fn -> AI.chat([msg("Search")], provider: :openai) end
        end

        merge do
          fn results -> Enum.map(results, fn {:ok, r} -> r.content end) end
        end
      end

      MyTeam.run()
  """

  @type agent_spec :: (() -> {:ok, term()} | {:error, term()} | term())
  @type merge_fn :: ([{:ok, term()} | {:error, term()}] -> term())

  @default_max_concurrency 5

  @doc """
  Executes agent specs in parallel and merges results.

  Each spec is a zero-arity function. Results are collected in input order
  and passed to `merge_fn`. Crashed specs produce `{:error, {:task_failed, reason}}`.

  ## Options

  - `:max_concurrency` — maximum parallel tasks (default: 5)
  - `:timeout` — per-task timeout in ms (default: `:infinity`)
  - `:ordered` — preserve input order in results (default: `true`)
  """
  @spec run([agent_spec()], merge_fn(), keyword()) :: {:ok, term()}
  def run(specs, merge_fn, opts \\ []) do
    max_concurrency = Keyword.get(opts, :max_concurrency, @default_max_concurrency)
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
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/phoenix_ai/team_test.exs --trace`
Expected: 1 test, 0 failures

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_ai/team.ex test/phoenix_ai/team_test.exs
git commit -m "feat(09): add Team.run/3 with parallel fan-out/fan-in execution"
```

---

### Task 2: Team.run/3 — Partial Errors + Crash Isolation

**Files:**
- Modify: `test/phoenix_ai/team_test.exs`

- [ ] **Step 1: Write the partial error test**

Add to the `describe "run/3"` block in `test/phoenix_ai/team_test.exs`:

```elixir
    test "partial errors are passed to merge, Team still returns {:ok, _}" do
      specs = [
        fn -> {:ok, "good_a"} end,
        fn -> {:error, :something_failed} end,
        fn -> {:ok, "good_c"} end
      ]

      merge_fn = fn results ->
        successes = for {:ok, val} <- results, do: val
        errors = for {:error, _} = err <- results, do: err
        %{successes: successes, errors: errors}
      end

      assert {:ok, %{successes: ["good_a", "good_c"], errors: [{:error, :something_failed}]}} =
               Team.run(specs, merge_fn)
    end
```

- [ ] **Step 2: Write the crash isolation test**

Add to the `describe "run/3"` block:

```elixir
    test "spec that raises is captured as {:error, {:task_failed, _}}, does not crash caller" do
      specs = [
        fn -> {:ok, "good"} end,
        fn -> raise "boom" end,
        fn -> {:ok, "also_good"} end
      ]

      merge_fn = fn results -> results end

      assert {:ok, results} = Team.run(specs, merge_fn)
      assert [{:ok, "good"}, {:error, {:task_failed, "boom"}}, {:ok, "also_good"}] = results
    end
```

- [ ] **Step 3: Run tests to verify they pass**

Run: `mix test test/phoenix_ai/team_test.exs --trace`
Expected: 3 tests, 0 failures

- [ ] **Step 4: Commit**

```bash
git add test/phoenix_ai/team_test.exs
git commit -m "test(09): add partial error and crash isolation tests for Team.run/3"
```

---

### Task 3: Team.run/3 — Edge Cases (empty specs, max_concurrency, ordering)

**Files:**
- Modify: `test/phoenix_ai/team_test.exs`

- [ ] **Step 1: Write the empty specs test**

Add to the `describe "run/3"` block:

```elixir
    test "empty specs list passes empty list to merge" do
      merge_fn = fn results -> length(results) end

      assert {:ok, 0} = Team.run([], merge_fn)
    end
```

- [ ] **Step 2: Write the max_concurrency test**

Add to the `describe "run/3"` block:

```elixir
    test "max_concurrency: 1 executes specs sequentially" do
      specs = [
        fn ->
          Process.sleep(50)
          {:ok, "a"}
        end,
        fn ->
          Process.sleep(50)
          {:ok, "b"}
        end,
        fn ->
          Process.sleep(50)
          {:ok, "c"}
        end
      ]

      merge_fn = fn results -> Enum.map(results, fn {:ok, v} -> v end) end

      {elapsed, {:ok, result}} = :timer.tc(fn -> Team.run(specs, merge_fn, max_concurrency: 1) end)

      assert result == ["a", "b", "c"]
      # Sequential: ~150ms minimum. Parallel would be ~50ms.
      assert elapsed > 120_000
    end
```

- [ ] **Step 3: Write the deterministic ordering test**

Add to the `describe "run/3"` block:

```elixir
    test "results are in the same order as specs regardless of completion time" do
      specs = [
        fn ->
          Process.sleep(100)
          {:ok, "slow"}
        end,
        fn ->
          {:ok, "fast"}
        end,
        fn ->
          Process.sleep(50)
          {:ok, "medium"}
        end
      ]

      merge_fn = fn results -> Enum.map(results, fn {:ok, v} -> v end) end

      assert {:ok, ["slow", "fast", "medium"]} = Team.run(specs, merge_fn)
    end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/phoenix_ai/team_test.exs --trace`
Expected: 6 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add test/phoenix_ai/team_test.exs
git commit -m "test(09): add edge case tests — empty specs, max_concurrency, ordering"
```

---

### Task 4: DSL Macro — Basic `use PhoenixAI.Team` + `agent/2` + `merge/1`

**Files:**
- Modify: `lib/phoenix_ai/team.ex`
- Create: `test/phoenix_ai/team_dsl_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
# test/phoenix_ai/team_dsl_test.exs
defmodule PhoenixAI.TeamDSLTest do
  use ExUnit.Case, async: true

  defmodule TwoAgentTeam do
    use PhoenixAI.Team

    agent :alpha do
      fn -> {:ok, "alpha_result"} end
    end

    agent :beta do
      fn -> {:ok, "beta_result"} end
    end

    merge do
      fn results ->
        results
        |> Enum.map(fn {:ok, val} -> val end)
        |> Enum.join(" + ")
      end
    end
  end

  describe "DSL module" do
    test "run/0 executes agents in parallel and merges results" do
      assert {:ok, "alpha_result + beta_result"} = TwoAgentTeam.run()
    end

    test "agents/0 returns list of functions" do
      agents = TwoAgentTeam.agents()
      assert length(agents) == 2
      assert is_function(hd(agents), 0)
    end

    test "agent_names/0 returns ordered atom list" do
      assert [:alpha, :beta] = TwoAgentTeam.agent_names()
    end

    test "merge_fn/0 returns the merge function" do
      assert is_function(TwoAgentTeam.merge_fn(), 1)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/phoenix_ai/team_dsl_test.exs --trace`
Expected: FAIL — `__using__/1` macro not defined

- [ ] **Step 3: Add DSL macros to Team module**

Add the following to `lib/phoenix_ai/team.ex` inside the module, before `run/3`:

```elixir
  defmacro __using__(_opts) do
    quote do
      import PhoenixAI.Team, only: [agent: 2, merge: 1]
      Module.register_attribute(__MODULE__, :team_agents, accumulate: true)
      Module.register_attribute(__MODULE__, :team_merge_fn, accumulate: false)
      @before_compile PhoenixAI.Team
    end
  end

  @doc """
  Defines a named agent spec in a team module.

  The block must return a zero-arity function `fn -> {:ok, result} | {:error, reason} end`.
  """
  defmacro agent(name, do: block) do
    escaped_block = Macro.escape(block)

    quote do
      @team_agents {unquote(name), unquote(escaped_block)}
    end
  end

  @doc """
  Defines the merge function for a team module.

  The block must return a function that accepts a list of result tuples.
  """
  defmacro merge(do: block) do
    escaped_block = Macro.escape(block)

    quote do
      @team_merge_fn unquote(escaped_block)
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    agents = Module.get_attribute(env.module, :team_agents) |> Enum.reverse()
    merge_fn_ast = Module.get_attribute(env.module, :team_merge_fn)

    agent_funs_ast = Enum.map(agents, fn {_name, fun_ast} -> fun_ast end)
    agent_names = Enum.map(agents, fn {name, _fun_ast} -> name end)

    quote do
      @doc "Returns the list of agent spec functions in definition order."
      def agents, do: unquote(agent_funs_ast)

      @doc "Returns the list of agent name atoms in definition order."
      def agent_names, do: unquote(agent_names)

      @doc "Returns the merge function."
      def merge_fn, do: unquote(merge_fn_ast)

      @doc "Runs the team with the given options."
      def run(opts \\ []) do
        PhoenixAI.Team.run(agents(), merge_fn(), opts)
      end
    end
  end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/phoenix_ai/team_dsl_test.exs --trace`
Expected: 4 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_ai/team.ex test/phoenix_ai/team_dsl_test.exs
git commit -m "feat(09): add Team DSL macro — use PhoenixAI.Team + agent/2 + merge/1"
```

---

### Task 5: DSL — Error Handling + Opts Passthrough

**Files:**
- Modify: `test/phoenix_ai/team_dsl_test.exs`

- [ ] **Step 1: Write the error handling test**

Add to `test/phoenix_ai/team_dsl_test.exs`:

```elixir
  defmodule ErrorTeam do
    use PhoenixAI.Team

    agent :good do
      fn -> {:ok, "success"} end
    end

    agent :bad do
      fn -> {:error, :broken} end
    end

    merge do
      fn results -> results end
    end
  end

  describe "DSL error handling" do
    test "failing agent result is included in merge input" do
      assert {:ok, [{:ok, "success"}, {:error, :broken}]} = ErrorTeam.run()
    end
  end
```

- [ ] **Step 2: Write the opts passthrough test**

Add to `test/phoenix_ai/team_dsl_test.exs`:

```elixir
  defmodule TimedTeam do
    use PhoenixAI.Team

    agent :slow_a do
      fn ->
        Process.sleep(50)
        {:ok, "a"}
      end
    end

    agent :slow_b do
      fn ->
        Process.sleep(50)
        {:ok, "b"}
      end
    end

    merge do
      fn results -> Enum.map(results, fn {:ok, v} -> v end) end
    end
  end

  describe "DSL opts passthrough" do
    test "run/1 passes max_concurrency to Team.run/3" do
      {elapsed, {:ok, result}} = :timer.tc(fn -> TimedTeam.run(max_concurrency: 1) end)

      assert result == ["a", "b"]
      # Sequential: ~100ms minimum
      assert elapsed > 80_000
    end
  end
```

- [ ] **Step 3: Run all DSL tests to verify they pass**

Run: `mix test test/phoenix_ai/team_dsl_test.exs --trace`
Expected: 6 tests, 0 failures

- [ ] **Step 4: Commit**

```bash
git add test/phoenix_ai/team_dsl_test.exs
git commit -m "test(09): add DSL error handling and opts passthrough tests"
```

---

### Task 6: Run Full Test Suite + Format Check

**Files:**
- No file changes expected

- [ ] **Step 1: Run the full test suite**

Run: `mix test --trace`
Expected: All existing tests still pass, plus the new 12 Team tests (6 in team_test, 6 in team_dsl_test)

- [ ] **Step 2: Run formatter**

Run: `mix format --check-formatted`
Expected: No formatting issues

- [ ] **Step 3: Run Credo**

Run: `mix credo --strict`
Expected: No new issues in `lib/phoenix_ai/team.ex` or test files

- [ ] **Step 4: Fix any issues found**

If formatter or Credo report issues, fix them in the relevant files.

- [ ] **Step 5: Commit fixes if any**

```bash
git add -A
git commit -m "style(09): fix formatting/credo issues in Team module"
```

(Skip this step if no issues were found)

---

## Verification

After all tasks complete, these success criteria from the roadmap must be TRUE:

1. **ORCH-04:** `PhoenixAI.Team.run(agent_specs, merge_fn)` starts all agents concurrently and returns only after all complete
2. **ORCH-05:** `max_concurrency: 5` is the default — no more than 5 agents run simultaneously without explicit override
3. **ORCH-06:** The merge function receives all results in deterministic order and its return value is the Team's return value
4. **Crash isolation:** A Task failure (agent crash) returns `{:error, {:task_failed, reason}}` and does not crash the caller

Run: `mix test test/phoenix_ai/team_test.exs test/phoenix_ai/team_dsl_test.exs --trace`
Expected: 12 tests, 0 failures
