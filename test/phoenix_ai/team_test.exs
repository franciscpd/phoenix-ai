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
  end
end
