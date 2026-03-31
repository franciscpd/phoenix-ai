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
end
