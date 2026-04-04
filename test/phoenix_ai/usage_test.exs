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

  describe "from_provider/2 with :anthropic" do
    test "maps Anthropic usage fields to normalized struct" do
      raw = %{
        "input_tokens" => 150,
        "output_tokens" => 80,
        "cache_creation_input_tokens" => 20,
        "cache_read_input_tokens" => 10
      }

      usage = Usage.from_provider(:anthropic, raw)

      assert usage.input_tokens == 150
      assert usage.output_tokens == 80
      assert usage.total_tokens == 230
      assert usage.cache_read_tokens == 10
      assert usage.cache_creation_tokens == 20
      assert usage.provider_specific == raw
    end

    test "auto-calculates total_tokens" do
      raw = %{"input_tokens" => 100, "output_tokens" => 50}

      usage = Usage.from_provider(:anthropic, raw)
      assert usage.total_tokens == 150
    end

    test "cache fields are nil when not present" do
      raw = %{"input_tokens" => 100, "output_tokens" => 50}

      usage = Usage.from_provider(:anthropic, raw)

      assert usage.cache_read_tokens == nil
      assert usage.cache_creation_tokens == nil
    end
  end

  describe "from_provider/2 with :openrouter" do
    test "delegates to OpenAI mapping" do
      raw = %{
        "prompt_tokens" => 150,
        "completion_tokens" => 80,
        "total_tokens" => 230,
        "native_tokens_prompt" => 145,
        "native_tokens_completion" => 78
      }

      usage = Usage.from_provider(:openrouter, raw)

      assert usage.input_tokens == 150
      assert usage.output_tokens == 80
      assert usage.total_tokens == 230
      assert usage.provider_specific == raw
    end

    test "nil returns zero-valued usage" do
      usage = Usage.from_provider(:openrouter, nil)

      assert usage.input_tokens == 0
      assert usage.output_tokens == 0
      assert usage.total_tokens == 0
      assert usage.provider_specific == %{}
    end

    test "empty map returns zero-valued usage" do
      usage = Usage.from_provider(:openrouter, %{})

      assert usage.input_tokens == 0
      assert usage.output_tokens == 0
      assert usage.total_tokens == 0
      assert usage.provider_specific == %{}
    end
  end

  describe "from_provider/2 with nil and empty map" do
    test "nil returns zero-valued usage" do
      usage = Usage.from_provider(:openai, nil)

      assert usage.input_tokens == 0
      assert usage.output_tokens == 0
      assert usage.total_tokens == 0
      assert usage.cache_read_tokens == nil
      assert usage.cache_creation_tokens == nil
      assert usage.provider_specific == %{}
    end

    test "empty map returns zero-valued usage" do
      usage = Usage.from_provider(:openai, %{})

      assert usage.input_tokens == 0
      assert usage.output_tokens == 0
      assert usage.total_tokens == 0
      assert usage.provider_specific == %{}
    end
  end

  describe "from_provider/2 with unknown provider" do
    test "fallback handles OpenAI-compatible format" do
      raw = %{
        "prompt_tokens" => 100,
        "completion_tokens" => 50,
        "total_tokens" => 150
      }

      usage = Usage.from_provider(:groq, raw)

      assert usage.input_tokens == 100
      assert usage.output_tokens == 50
      assert usage.total_tokens == 150
      assert usage.provider_specific == raw
    end

    test "fallback handles Anthropic-style format" do
      raw = %{
        "input_tokens" => 100,
        "output_tokens" => 50,
        "cache_read_input_tokens" => 5
      }

      usage = Usage.from_provider(:custom, raw)

      assert usage.input_tokens == 100
      assert usage.output_tokens == 50
      assert usage.total_tokens == 150
      assert usage.cache_read_tokens == 5
      assert usage.provider_specific == raw
    end

    test "fallback auto-calculates total_tokens when missing" do
      raw = %{"prompt_tokens" => 30, "completion_tokens" => 20}

      usage = Usage.from_provider(:together, raw)
      assert usage.total_tokens == 50
    end
  end
end
