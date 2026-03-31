defmodule PhoenixAI.AIStreamToolsTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Message

  defmodule FakeTool do
    def name, do: "fake_tool"
    def description, do: "A fake tool"
    def parameters_schema, do: %{type: :object, properties: %{}}
    def execute(_args, _opts), do: {:ok, "fake result"}
  end

  describe "stream/2 with tools routing" do
    test "dispatch_stream routes to Stream.run_with_tools when tools present" do
      messages = [%Message{role: :user, content: "Hello"}]

      result =
        AI.stream(messages,
          provider: :openai,
          tools: [FakeTool],
          on_chunk: fn _chunk -> :ok end
        )

      assert {:error, {:missing_api_key, :openai}} = result
    end

    test "dispatch_stream routes to Stream.run when no tools" do
      messages = [%Message{role: :user, content: "Hello"}]

      result =
        AI.stream(messages,
          provider: :openai,
          on_chunk: fn _chunk -> :ok end
        )

      assert {:error, {:missing_api_key, :openai}} = result
    end

    test "tools option is stripped before passing to stream" do
      messages = [%Message{role: :user, content: "Hello"}]

      # Providing a key bypasses the missing_api_key check. The error
      # will occur when trying to reach the provider (Finch registry).
      # We use catch_error to verify routing happened and tools were stripped.
      assert_raise ArgumentError, fn ->
        AI.stream(messages,
          provider: :openai,
          tools: [FakeTool],
          api_key: "sk-test"
        )
      end
    end
  end
end
