defmodule PhoenixAI.StreamTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.{Response, Stream, StreamChunk}
  alias PhoenixAI.Usage

  defmodule FakeOpenAIProvider do
    alias PhoenixAI.{StreamChunk, Usage}

    def parse_chunk(%{data: "[DONE]"}), do: %StreamChunk{finish_reason: "stop"}

    def parse_chunk(%{data: data}) do
      json = Jason.decode!(data)
      choice = json |> Map.get("choices", []) |> List.first(%{})
      delta = Map.get(choice, "delta", %{})
      raw_usage = Map.get(json, "usage")

      %StreamChunk{
        delta: Map.get(delta, "content"),
        finish_reason: Map.get(choice, "finish_reason"),
        usage: if(raw_usage, do: Usage.from_provider(:openai, raw_usage), else: nil)
      }
    end
  end

  describe "process_sse_events/2" do
    test "processes SSE events into chunks and accumulates content" do
      sse_data =
        "event: message\ndata: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}]}\n\nevent: message\ndata: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\" world\"},\"finish_reason\":null}]}\n\nevent: message\ndata: [DONE]\n\n"

      callback = fn chunk -> send(self(), {:chunk, chunk}) end

      acc = %{
        remainder: "",
        provider_mod: FakeOpenAIProvider,
        callback: callback,
        content: "",
        usage: nil,
        finished: false
      }

      result = Stream.process_sse_events(sse_data, acc)

      assert result.content == "Hello world"
      assert result.finished == true
      assert_received {:chunk, %StreamChunk{delta: "Hello"}}
      assert_received {:chunk, %StreamChunk{delta: " world"}}
    end

    test "handles fragmented SSE data across multiple calls" do
      fragment1 = "event: message\ndata: {\"choices\":[{\"index\":0,\"delta\":{\"conten"

      callback = fn chunk -> send(self(), {:chunk, chunk}) end

      acc = %{
        remainder: "",
        provider_mod: FakeOpenAIProvider,
        callback: callback,
        content: "",
        usage: nil,
        finished: false
      }

      result1 = Stream.process_sse_events(fragment1, acc)
      assert result1.content == ""
      refute_received {:chunk, _}

      fragment2 =
        "t\":\"Hi\"},\"finish_reason\":null}]}\n\nevent: message\ndata: [DONE]\n\n"

      result2 = Stream.process_sse_events(fragment2, result1)

      assert result2.content == "Hi"
      assert result2.finished == true
      assert_received {:chunk, %StreamChunk{delta: "Hi"}}
    end

    test "ignores nil chunks from provider" do
      defmodule NilChunkProvider do
        def parse_chunk(_), do: nil
      end

      sse_data = "event: ping\ndata: \n\n"

      callback = fn chunk -> send(self(), {:chunk, chunk}) end

      acc = %{
        remainder: "",
        provider_mod: NilChunkProvider,
        callback: callback,
        content: "",
        usage: nil,
        finished: false
      }

      result = Stream.process_sse_events(sse_data, acc)
      assert result.content == ""
      refute_received {:chunk, _}
    end

    test "captures usage from chunk with usage field" do
      sse_data =
        "event: message\ndata: {\"choices\":[],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":5,\"total_tokens\":15}}\n\nevent: message\ndata: [DONE]\n\n"

      callback = fn _chunk -> :ok end

      acc = %{
        remainder: "",
        provider_mod: FakeOpenAIProvider,
        callback: callback,
        content: "",
        usage: nil,
        finished: false
      }

      result = Stream.process_sse_events(sse_data, acc)

      assert %Usage{input_tokens: 10, output_tokens: 5, total_tokens: 15} = result.usage
    end

    test "handles JSON decode errors gracefully" do
      sse_data = "event: message\ndata: {invalid json}\n\n"

      callback = fn _chunk -> :ok end

      acc = %{
        remainder: "",
        provider_mod: FakeOpenAIProvider,
        callback: callback,
        content: "",
        usage: nil,
        finished: false
      }

      result = Stream.process_sse_events(sse_data, acc)
      assert result.content == ""
    end
  end

  describe "SSE fixture integration" do
    test "parses complete OpenAI SSE fixture" do
      raw = File.read!("test/fixtures/sse/openai_simple.sse")

      callback = fn chunk -> send(self(), {:chunk, chunk}) end

      acc = %{
        remainder: "",
        provider_mod: FakeOpenAIProvider,
        callback: callback,
        content: "",
        usage: nil,
        finished: false
      }

      result = Stream.process_sse_events(raw, acc)

      assert result.content == "Hello world"
      assert result.finished == true
      assert_received {:chunk, %StreamChunk{delta: "Hello"}}
      assert_received {:chunk, %StreamChunk{delta: " world"}}
    end

    test "handles OpenAI SSE fragmented at arbitrary byte positions" do
      raw = File.read!("test/fixtures/sse/openai_fragmented.sse")

      for split_pos <- [10, 30, 50, div(byte_size(raw), 2)] do
        callback = fn chunk -> send(self(), {:chunk, chunk}) end

        acc = %{
          remainder: "",
          provider_mod: FakeOpenAIProvider,
          callback: callback,
          content: "",
          usage: nil,
          finished: false
        }

        {frag1, frag2} = String.split_at(raw, split_pos)

        acc = Stream.process_sse_events(frag1, acc)
        result = Stream.process_sse_events(frag2, acc)

        assert result.content == "Fragmented",
               "Failed at split_pos=#{split_pos}: got #{inspect(result.content)}"

        assert result.finished == true
      end
    end

    test "parses complete Anthropic SSE fixture" do
      raw = File.read!("test/fixtures/sse/anthropic_simple.sse")

      defmodule FakeAnthropicProvider do
        alias PhoenixAI.{StreamChunk, Usage}

        def parse_chunk(%{event: "content_block_delta", data: data}) do
          json = Jason.decode!(data)
          %StreamChunk{delta: get_in(json, ["delta", "text"])}
        end

        def parse_chunk(%{event: "message_delta", data: data}) do
          json = Jason.decode!(data)
          raw_usage = Map.get(json, "usage")

          %StreamChunk{
            finish_reason: get_in(json, ["delta", "stop_reason"]),
            usage: if(raw_usage, do: Usage.from_provider(:anthropic, raw_usage), else: nil)
          }
        end

        def parse_chunk(%{event: "message_stop", data: _}),
          do: %StreamChunk{finish_reason: "stop"}

        def parse_chunk(_), do: nil
      end

      callback = fn chunk -> send(self(), {:chunk, chunk}) end

      acc = %{
        remainder: "",
        provider_mod: FakeAnthropicProvider,
        callback: callback,
        content: "",
        usage: nil,
        finished: false
      }

      result = Stream.process_sse_events(raw, acc)

      assert result.content == "Hello world"
      assert result.finished == true
      assert %Usage{output_tokens: 2} = result.usage
      assert_received {:chunk, %StreamChunk{delta: "Hello"}}
      assert_received {:chunk, %StreamChunk{delta: " world"}}
    end
  end

  describe "build_response/1" do
    test "builds Response struct from accumulated state" do
      acc = %{content: "Hello world", usage: %Usage{total_tokens: 10}, finished: true}
      response = Stream.build_response(acc)
      assert %Response{content: "Hello world", usage: %Usage{total_tokens: 10}} = response
    end

    test "handles nil usage" do
      acc = %{content: "test", usage: nil, finished: true}
      response = Stream.build_response(acc)
      assert %Response{content: "test", usage: %Usage{}} = response
    end
  end

  describe "tool call delta accumulation" do
    defmodule ToolCallProvider do
      alias PhoenixAI.StreamChunk

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
          raw_usage = Map.get(json, "usage")

          %StreamChunk{
            delta: Map.get(delta, "content"),
            finish_reason: Map.get(choice, "finish_reason"),
            usage: if(raw_usage, do: PhoenixAI.Usage.from_provider(:openai, raw_usage), else: nil)
          }
        end
      end
    end

    test "accumulates tool call deltas into complete tool calls" do
      chunks = [
        ~s(event: message\ndata: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_abc","function":{"name":"get_weather","arguments":""}}]},"finish_reason":null}]}\n\n),
        ~s(event: message\ndata: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\\\"city\\\":"}}]},"finish_reason":null}]}\n\n),
        ~s(event: message\ndata: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":" \\\"London\\\"}"}}]},"finish_reason":null}]}\n\n),
        ~s(event: message\ndata: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}\n\n),
        ~s(event: message\ndata: [DONE]\n\n)
      ]

      callback = fn chunk -> send(self(), {:chunk, chunk}) end

      acc = %{
        remainder: "",
        provider_mod: ToolCallProvider,
        callback: callback,
        content: "",
        usage: nil,
        finished: false,
        status: nil,
        tool_calls_acc: %{}
      }

      final_acc =
        Enum.reduce(chunks, acc, fn chunk_data, acc ->
          Stream.process_sse_events(chunk_data, acc)
        end)

      assert final_acc.tool_calls_acc[0].id == "call_abc"
      assert final_acc.tool_calls_acc[0].name == "get_weather"
      assert final_acc.tool_calls_acc[0].arguments == "{\"city\": \"London\"}"

      # Tool call delta chunks are delivered to callback
      assert_received {:chunk, %StreamChunk{tool_call_delta: %{name: "get_weather"}}}
    end

    test "build_response converts tool_calls_acc to ToolCall structs" do
      acc = %{
        content: "Let me check the weather.",
        usage: %Usage{input_tokens: 10, output_tokens: 20, total_tokens: 30},
        tool_calls_acc: %{
          0 => %{id: "call_abc", name: "get_weather", arguments: ~s({"city": "London"})},
          1 => %{id: "call_def", name: "get_time", arguments: ~s({"timezone": "UTC"})}
        }
      }

      response = Stream.build_response(acc)

      assert %PhoenixAI.Response{} = response
      assert response.content == "Let me check the weather."
      assert length(response.tool_calls) == 2

      [tc0, tc1] = response.tool_calls
      assert tc0.id == "call_abc"
      assert tc0.name == "get_weather"
      assert tc0.arguments == %{"city" => "London"}
      assert tc1.id == "call_def"
      assert tc1.name == "get_time"
      assert tc1.arguments == %{"timezone" => "UTC"}
    end

    test "build_response handles empty tool_calls_acc" do
      acc = %{
        content: "Hello world",
        usage: %Usage{},
        tool_calls_acc: %{}
      }

      response = Stream.build_response(acc)
      assert response.tool_calls == []
    end

    test "build_response handles empty arguments string" do
      acc = %{
        content: "",
        usage: nil,
        tool_calls_acc: %{
          0 => %{id: "call_abc", name: "no_args_tool", arguments: ""}
        }
      }

      response = Stream.build_response(acc)
      [tc] = response.tool_calls
      assert tc.arguments == %{}
    end
  end
end
