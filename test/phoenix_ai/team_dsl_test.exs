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

  describe "DSL error handling" do
    test "failing agent result is included in merge input" do
      assert {:ok, [{:ok, "success"}, {:error, :broken}]} = ErrorTeam.run()
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
end
