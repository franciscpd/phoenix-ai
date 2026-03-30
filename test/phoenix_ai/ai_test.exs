defmodule AITest do
  use ExUnit.Case, async: false

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

    test "resolves :anthropic to a loaded provider module" do
      mod = AI.provider_module(:anthropic)
      assert Code.ensure_loaded?(mod)
    end

    test "resolves :openrouter to a loaded provider module" do
      mod = AI.provider_module(:openrouter)
      assert Code.ensure_loaded?(mod)
    end

    test "delegates to Anthropic adapter via mock" do
      expect(PhoenixAI.MockProvider, :chat, fn messages, opts ->
        assert [%PhoenixAI.Message{role: :user, content: "Hi"}] = messages
        assert opts[:model] == "claude-sonnet-4-5"
        {:ok, %PhoenixAI.Response{content: "Bonjour!"}}
      end)

      result =
        AI.chat(
          [%PhoenixAI.Message{role: :user, content: "Hi"}],
          provider: PhoenixAI.MockProvider,
          model: "claude-sonnet-4-5",
          api_key: "test-key"
        )

      assert {:ok, %PhoenixAI.Response{content: "Bonjour!"}} = result
    end

    test "delegates to OpenRouter adapter via mock" do
      expect(PhoenixAI.MockProvider, :chat, fn messages, opts ->
        assert [%PhoenixAI.Message{role: :user, content: "Hi"}] = messages
        assert opts[:model] == "anthropic/claude-sonnet-4-5"
        {:ok, %PhoenixAI.Response{content: "Hello via OpenRouter!"}}
      end)

      result =
        AI.chat(
          [%PhoenixAI.Message{role: :user, content: "Hi"}],
          provider: PhoenixAI.MockProvider,
          model: "anthropic/claude-sonnet-4-5",
          api_key: "test-key"
        )

      assert {:ok, %PhoenixAI.Response{content: "Hello via OpenRouter!"}} = result
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

    test "routes to ToolLoop when tools option is present" do
      PhoenixAI.MockProvider
      |> expect(:format_tools, fn tools ->
        assert [PhoenixAI.TestTools.WeatherTool] = tools
        [%{"type" => "function", "function" => %{"name" => "get_weather"}}]
      end)
      |> expect(:chat, fn _messages, opts ->
        assert opts[:tools_json] != nil
        {:ok, %PhoenixAI.Response{content: "It's sunny!", tool_calls: [], finish_reason: "stop"}}
      end)

      result =
        AI.chat(
          [%PhoenixAI.Message{role: :user, content: "Weather?"}],
          provider: PhoenixAI.MockProvider,
          api_key: "test-key",
          tools: [PhoenixAI.TestTools.WeatherTool]
        )

      assert {:ok, %PhoenixAI.Response{content: "It's sunny!"}} = result
    end

    test "without tools option, does not invoke ToolLoop" do
      expect(PhoenixAI.MockProvider, :chat, fn _messages, opts ->
        refute Keyword.has_key?(opts, :tools_json)
        {:ok, %PhoenixAI.Response{content: "Hello!", tool_calls: []}}
      end)

      result =
        AI.chat(
          [%PhoenixAI.Message{role: :user, content: "Hi"}],
          provider: PhoenixAI.MockProvider,
          api_key: "test-key"
        )

      assert {:ok, %PhoenixAI.Response{content: "Hello!"}} = result
    end
  end
end
