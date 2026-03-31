defmodule PhoenixAI.StreamToolsTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.{Message, Response, Stream, StreamChunk, ToolCall}

  defmodule WeatherTool do
    def name, do: "get_weather"
    def description, do: "Get the weather"
    def parameters_schema, do: %{type: :object, properties: %{city: %{type: :string}}}
    def execute(%{"city" => city}, _opts), do: {:ok, "Sunny in #{city}"}
  end

  defmodule FakeStreamProvider do
    @moduledoc false
    alias PhoenixAI.StreamChunk

    def format_messages(messages), do: Enum.map(messages, fn m -> %{"role" => to_string(m.role)} end)
    def format_tools(_tools), do: [%{"type" => "function", "function" => %{"name" => "get_weather"}}]

    def build_stream_body(model, formatted_messages, opts) do
      %{"model" => model, "messages" => formatted_messages, "stream" => true}
      |> maybe_put("tools", Keyword.get(opts, :tools_json))
    end

    def stream_url(_opts), do: "https://fake.api/chat/completions"
    def stream_headers(_opts), do: [{"authorization", "Bearer fake"}]

    def parse_chunk(%{data: "[DONE]"}), do: %StreamChunk{finish_reason: "stop"}

    def parse_chunk(%{data: data}) do
      json = Jason.decode!(data)
      choice = json |> Map.get("choices", []) |> List.first(%{})
      delta = Map.get(choice, "delta", %{})

      tool_calls = Map.get(delta, "tool_calls")

      if tool_calls do
        [tc | _] = tool_calls
        function = Map.get(tc, "function", %{})

        %StreamChunk{
          tool_call_delta: %{
            index: Map.get(tc, "index", 0),
            id: Map.get(tc, "id"),
            name: Map.get(function, "name"),
            arguments: Map.get(function, "arguments", "")
          }
        }
      else
        %StreamChunk{
          delta: Map.get(delta, "content"),
          finish_reason: Map.get(choice, "finish_reason"),
          usage: Map.get(json, "usage")
        }
      end
    end

    defp maybe_put(map, _key, nil), do: map
    defp maybe_put(map, key, value), do: Map.put(map, key, value)
  end

  describe "run_with_tools/5" do
    test "returns {:error, :max_iterations_reached} when limit exceeded" do
      result = Stream.run_with_tools(FakeStreamProvider, [], fn _ -> nil end, [WeatherTool], max_iterations: 0)
      assert {:error, :max_iterations_reached} = result
    end
  end

  describe "tool call fixture parsing" do
    test "OpenAI fixture produces correct tool calls via process_sse_events" do
      raw = File.read!("test/fixtures/sse/openai_tool_call.sse")
      chunks = fn _chunk -> :ok end

      acc = %{
        remainder: "",
        provider_mod: PhoenixAI.Providers.OpenAI,
        callback: chunks,
        content: "",
        usage: nil,
        finished: false,
        status: nil,
        tool_calls_acc: %{}
      }

      final_acc = Stream.process_sse_events(raw, acc)

      assert final_acc.content == "Let me check."
      assert final_acc.tool_calls_acc[0].id == "call_abc123"
      assert final_acc.tool_calls_acc[0].name == "get_weather"
      assert final_acc.tool_calls_acc[0].arguments == "{\"city\": \"London\"}"
      assert final_acc.finished == true

      response = Stream.build_response(final_acc)
      assert [%ToolCall{name: "get_weather", arguments: %{"city" => "London"}}] = response.tool_calls
    end

    test "Anthropic fixture produces correct tool calls via process_sse_events" do
      raw = File.read!("test/fixtures/sse/anthropic_tool_call.sse")
      chunks = fn _chunk -> :ok end

      acc = %{
        remainder: "",
        provider_mod: PhoenixAI.Providers.Anthropic,
        callback: chunks,
        content: "",
        usage: nil,
        finished: false,
        status: nil,
        tool_calls_acc: %{}
      }

      final_acc = Stream.process_sse_events(raw, acc)

      assert final_acc.content == "Let me check."
      assert final_acc.tool_calls_acc[1].id == "toolu_abc123"
      assert final_acc.tool_calls_acc[1].name == "get_weather"
      assert String.contains?(final_acc.tool_calls_acc[1].arguments, "London")
      assert final_acc.finished == true

      response = Stream.build_response(final_acc)
      assert [%ToolCall{name: "get_weather"}] = response.tool_calls
    end

    test "tool call delta chunks are delivered to callback" do
      raw = File.read!("test/fixtures/sse/openai_tool_call.sse")
      callback = fn chunk -> send(self(), {:chunk, chunk}) end

      acc = %{
        remainder: "",
        provider_mod: PhoenixAI.Providers.OpenAI,
        callback: callback,
        content: "",
        usage: nil,
        finished: false,
        status: nil,
        tool_calls_acc: %{}
      }

      Stream.process_sse_events(raw, acc)

      assert_received {:chunk, %StreamChunk{delta: "Let me"}}
      assert_received {:chunk, %StreamChunk{delta: " check."}}
      assert_received {:chunk, %StreamChunk{tool_call_delta: %{name: "get_weather"}}}
    end
  end
end
