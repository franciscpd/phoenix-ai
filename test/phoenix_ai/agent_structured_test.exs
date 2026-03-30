defmodule PhoenixAI.AgentStructuredTest do
  use ExUnit.Case, async: false

  import Mox

  alias PhoenixAI.{Agent, Response}

  @schema %{
    type: :object,
    properties: %{
      name: %{type: :string},
      age: %{type: :integer}
    },
    required: [:name, :age]
  }

  setup :set_mox_global
  setup :verify_on_exit!

  describe "prompt/2 with schema" do
    test "validates response and populates parsed" do
      expect(PhoenixAI.MockProvider, :chat, fn _messages, opts ->
        assert opts[:schema_json] != nil
        {:ok, %Response{content: ~s({"name":"Alice","age":30}), tool_calls: []}}
      end)

      {:ok, pid} =
        Agent.start_link(
          provider: PhoenixAI.MockProvider,
          api_key: "test-key",
          schema: @schema
        )

      assert {:ok, %Response{parsed: %{"name" => "Alice", "age" => 30}}} =
               Agent.prompt(pid, "Who?")
    end

    test "returns validation_failed for bad JSON shape" do
      expect(PhoenixAI.MockProvider, :chat, fn _messages, _opts ->
        {:ok, %Response{content: ~s({"name":"Alice"}), tool_calls: []}}
      end)

      {:ok, pid} =
        Agent.start_link(
          provider: PhoenixAI.MockProvider,
          api_key: "test-key",
          schema: @schema
        )

      assert {:error, {:validation_failed, details}} = Agent.prompt(pid, "Who?")
      assert "age" in details.missing_keys
    end

    test "returns invalid_json for non-JSON response" do
      expect(PhoenixAI.MockProvider, :chat, fn _messages, _opts ->
        {:ok, %Response{content: "Not JSON", tool_calls: []}}
      end)

      {:ok, pid} =
        Agent.start_link(
          provider: PhoenixAI.MockProvider,
          api_key: "test-key",
          schema: @schema
        )

      assert {:error, {:invalid_json, "Not JSON"}} = Agent.prompt(pid, "Who?")
    end

    test "without schema, parsed is nil" do
      expect(PhoenixAI.MockProvider, :chat, fn _messages, _opts ->
        {:ok, %Response{content: "Hello!", tool_calls: []}}
      end)

      {:ok, pid} =
        Agent.start_link(
          provider: PhoenixAI.MockProvider,
          api_key: "test-key"
        )

      assert {:ok, %Response{content: "Hello!", parsed: nil}} = Agent.prompt(pid, "Hi")
    end

    test "schema works with behaviour module" do
      expect(PhoenixAI.MockProvider, :chat, fn _messages, opts ->
        assert opts[:schema_json]["required"] == ["sentiment", "confidence"]
        {:ok, %Response{content: ~s({"sentiment":"positive","confidence":0.9}), tool_calls: []}}
      end)

      {:ok, pid} =
        Agent.start_link(
          provider: PhoenixAI.MockProvider,
          api_key: "test-key",
          schema: PhoenixAI.TestSchemas.SentimentSchema
        )

      assert {:ok, %Response{parsed: %{"sentiment" => "positive", "confidence" => 0.9}}} =
               Agent.prompt(pid, "Analyze")
    end
  end
end
