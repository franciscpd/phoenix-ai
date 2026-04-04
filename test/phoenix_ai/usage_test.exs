defmodule PhoenixAI.UsageTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Usage

  describe "struct" do
    test "has expected default values" do
      usage = %Usage{}
      assert usage.input_tokens == 0
      assert usage.output_tokens == 0
      assert usage.total_tokens == 0
      assert usage.cache_read_tokens == nil
      assert usage.cache_creation_tokens == nil
      assert usage.provider_specific == %{}
    end
  end

  describe "from_provider/2 with :openai" do
    test "maps OpenAI usage fields to normalized struct" do
      raw = %{
        "prompt_tokens" => 150,
        "completion_tokens" => 80,
        "total_tokens" => 230
      }

      usage = Usage.from_provider(:openai, raw)

      assert usage.input_tokens == 150
      assert usage.output_tokens == 80
      assert usage.total_tokens == 230
      assert usage.cache_read_tokens == nil
      assert usage.cache_creation_tokens == nil
      assert usage.provider_specific == raw
    end

    test "auto-calculates total_tokens when provider returns 0" do
      raw = %{
        "prompt_tokens" => 100,
        "completion_tokens" => 50,
        "total_tokens" => 0
      }

      usage = Usage.from_provider(:openai, raw)
      assert usage.total_tokens == 150
    end

    test "handles missing fields with zero defaults" do
      raw = %{"prompt_tokens" => 42}

      usage = Usage.from_provider(:openai, raw)

      assert usage.input_tokens == 42
      assert usage.output_tokens == 0
      assert usage.total_tokens == 42
    end
  end
end
