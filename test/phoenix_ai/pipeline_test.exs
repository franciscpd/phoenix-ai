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

    test "empty steps list returns {:ok, input}" do
      assert {:ok, "unchanged"} = Pipeline.run([], "unchanged")
    end

    test "non-tuple return is auto-wrapped in {:ok, value}" do
      steps = [
        fn input -> String.upcase(input) end,
        fn input -> {:ok, input <> "!"} end
      ]

      assert {:ok, "HELLO!"} = Pipeline.run(steps, "hello")
    end

    test "step that raises propagates the exception" do
      steps = [
        fn _input -> raise "boom" end
      ]

      assert_raise RuntimeError, "boom", fn ->
        Pipeline.run(steps, "hello")
      end
    end
  end
end
