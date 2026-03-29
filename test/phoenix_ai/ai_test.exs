defmodule AITest do
  use ExUnit.Case, async: true

  import Mox

  setup :verify_on_exit!

  describe "chat/2" do
    test "delegates to mock provider" do
      expect(PhoenixAI.MockProvider, :chat, fn messages, opts ->
        assert [%PhoenixAI.Message{role: :user, content: "Hi"}] = messages
        assert opts[:model] == "test-model"
        {:ok, %PhoenixAI.Response{content: "Hello!"}}
      end)

      result =
        AI.chat(
          [%PhoenixAI.Message{role: :user, content: "Hi"}],
          provider: PhoenixAI.MockProvider,
          model: "test-model",
          api_key: "test-key"
        )

      assert {:ok, %PhoenixAI.Response{content: "Hello!"}} = result
    end

    test "resolves :openai atom to OpenAI module" do
      assert AI.provider_module(:openai) == PhoenixAI.Providers.OpenAI
    end

    test "resolves :anthropic atom to Anthropic module" do
      assert AI.provider_module(:anthropic) == PhoenixAI.Providers.Anthropic
    end

    test "resolves :openrouter atom to OpenRouter module" do
      assert AI.provider_module(:openrouter) == PhoenixAI.Providers.OpenRouter
    end

    test "passes through custom module directly" do
      assert AI.provider_module(PhoenixAI.MockProvider) == PhoenixAI.MockProvider
    end

    test "returns error for unknown provider atom" do
      result =
        AI.chat(
          [%PhoenixAI.Message{role: :user, content: "Hi"}],
          provider: :unknown_provider,
          api_key: "test"
        )

      assert {:error, {:unknown_provider, :unknown_provider}} = result
    end

    test "returns error when api_key is missing" do
      System.delete_env("OPENAI_API_KEY")
      Application.delete_env(:phoenix_ai, :openai)

      result =
        AI.chat(
          [%PhoenixAI.Message{role: :user, content: "Hi"}],
          provider: :openai
        )

      assert {:error, {:missing_api_key, :openai}} = result
    end
  end
end
