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
