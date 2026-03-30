defmodule AIStructuredTest do
  use ExUnit.Case, async: false

  import Mox

  alias PhoenixAI.{Message, Response}

  setup :verify_on_exit!

  @schema %{
    type: :object,
    properties: %{
      name: %{type: :string},
      age: %{type: :integer}
    },
    required: [:name, :age]
  }

  describe "chat/2 with schema option" do
    test "resolves schema, passes schema_json to provider, validates and populates parsed" do
      expect(PhoenixAI.MockProvider, :chat, fn _messages, opts ->
        assert opts[:schema_json] == %{
                 "type" => "object",
                 "properties" => %{
                   "name" => %{"type" => "string"},
                   "age" => %{"type" => "integer"}
                 },
                 "required" => ["name", "age"]
               }

        {:ok, %Response{content: ~s({"name":"Alice","age":30}), tool_calls: []}}
      end)

      result =
        AI.chat(
          [%Message{role: :user, content: "Who?"}],
          provider: PhoenixAI.MockProvider,
          api_key: "test-key",
          schema: @schema
        )

      assert {:ok, %Response{parsed: %{"name" => "Alice", "age" => 30}}} = result
    end

    test "returns invalid_json when provider returns non-JSON content" do
      expect(PhoenixAI.MockProvider, :chat, fn _messages, _opts ->
        {:ok, %Response{content: "Not JSON at all", tool_calls: []}}
      end)

      result =
        AI.chat(
          [%Message{role: :user, content: "Who?"}],
          provider: PhoenixAI.MockProvider,
          api_key: "test-key",
          schema: @schema
        )

      assert {:error, {:invalid_json, "Not JSON at all"}} = result
    end

    test "returns validation_failed when JSON doesn't match schema" do
      expect(PhoenixAI.MockProvider, :chat, fn _messages, _opts ->
        {:ok, %Response{content: ~s({"name":"Alice"}), tool_calls: []}}
      end)

      result =
        AI.chat(
          [%Message{role: :user, content: "Who?"}],
          provider: PhoenixAI.MockProvider,
          api_key: "test-key",
          schema: @schema
        )

      assert {:error, {:validation_failed, details}} = result
      assert "age" in details.missing_keys
    end

    test "without schema option, does not validate or set parsed" do
      expect(PhoenixAI.MockProvider, :chat, fn _messages, opts ->
        refute Keyword.has_key?(opts, :schema_json)
        {:ok, %Response{content: "Hello!", tool_calls: []}}
      end)

      result =
        AI.chat(
          [%Message{role: :user, content: "Hi"}],
          provider: PhoenixAI.MockProvider,
          api_key: "test-key"
        )

      assert {:ok, %Response{content: "Hello!", parsed: nil}} = result
    end

    test "schema works with tools (ToolLoop path)" do
      PhoenixAI.MockProvider
      |> expect(:format_tools, fn tools ->
        assert [PhoenixAI.TestTools.WeatherTool] = tools
        [%{"type" => "function", "function" => %{"name" => "get_weather"}}]
      end)
      |> expect(:chat, fn _messages, opts ->
        assert opts[:schema_json] != nil
        assert opts[:tools_json] != nil
        {:ok, %Response{content: ~s({"name":"Weather","age":1}), tool_calls: []}}
      end)

      result =
        AI.chat(
          [%Message{role: :user, content: "Weather?"}],
          provider: PhoenixAI.MockProvider,
          api_key: "test-key",
          tools: [PhoenixAI.TestTools.WeatherTool],
          schema: @schema
        )

      assert {:ok, %Response{parsed: %{"name" => "Weather", "age" => 1}}} = result
    end

    test "schema works with behaviour module" do
      expect(PhoenixAI.MockProvider, :chat, fn _messages, opts ->
        assert opts[:schema_json]["required"] == ["sentiment", "confidence"]
        {:ok, %Response{content: ~s({"sentiment":"positive","confidence":0.95}), tool_calls: []}}
      end)

      result =
        AI.chat(
          [%Message{role: :user, content: "Analyze"}],
          provider: PhoenixAI.MockProvider,
          api_key: "test-key",
          schema: PhoenixAI.TestSchemas.SentimentSchema
        )

      assert {:ok, %Response{parsed: %{"sentiment" => "positive", "confidence" => 0.95}}} = result
    end
  end
end
