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
