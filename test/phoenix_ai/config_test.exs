defmodule PhoenixAI.ConfigTest do
  use ExUnit.Case, async: false

  alias PhoenixAI.Config

  describe "resolve/2" do
    test "call-site opts take precedence over everything" do
      opts = Config.resolve(:openai, api_key: "call-site-key", model: "gpt-4o-mini")
      assert opts[:api_key] == "call-site-key"
      assert opts[:model] == "gpt-4o-mini"
    end

    test "falls back to application config" do
      Application.put_env(:phoenix_ai, :openai, api_key: "config-key")
      opts = Config.resolve(:openai, [])
      assert opts[:api_key] == "config-key"
    after
      Application.delete_env(:phoenix_ai, :openai)
    end

    test "falls back to env var when no config" do
      System.put_env("OPENAI_API_KEY", "env-key")
      opts = Config.resolve(:openai, [])
      assert opts[:api_key] == "env-key"
    after
      System.delete_env("OPENAI_API_KEY")
    end

    test "applies default model for openai" do
      opts = Config.resolve(:openai, api_key: "test")
      assert opts[:model] == "gpt-4o"
    end

    test "applies default model for anthropic without date suffix" do
      opts = Config.resolve(:anthropic, api_key: "test")
      assert opts[:model] == "claude-sonnet-4-5"
    end

    test "no default model for openrouter" do
      opts = Config.resolve(:openrouter, api_key: "test")
      assert opts[:model] == nil
    end

    test "call-site model overrides default" do
      opts = Config.resolve(:openai, api_key: "test", model: "gpt-3.5-turbo")
      assert opts[:model] == "gpt-3.5-turbo"
    end

    test "cascade order: call-site > config > env > defaults" do
      System.put_env("OPENAI_API_KEY", "env-key")
      Application.put_env(:phoenix_ai, :openai, api_key: "config-key", model: "config-model")

      opts = Config.resolve(:openai, model: "call-site-model")
      assert opts[:api_key] == "config-key"
      assert opts[:model] == "call-site-model"
    after
      System.delete_env("OPENAI_API_KEY")
      Application.delete_env(:phoenix_ai, :openai)
    end
  end
end
