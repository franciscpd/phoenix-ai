defmodule PhoenixAI.StreamTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.{Response, Stream, StreamChunk}

  defmodule FakeOpenAIProvider do
    alias PhoenixAI.StreamChunk

    def parse_chunk(%{data: "[DONE]"}), do: %StreamChunk{finish_reason: "stop"}

    def parse_chunk(%{data: data}) do
      json = Jason.decode!(data)
      choice = json |> Map.get("choices", []) |> List.first(%{})
      delta = Map.get(choice, "delta", %{})

      %StreamChunk{
        delta: Map.get(delta, "content"),
        finish_reason: Map.get(choice, "finish_reason"),
        usage: Map.get(json, "usage")
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

      assert result.usage == %{
               "prompt_tokens" => 10,
               "completion_tokens" => 5,
               "total_tokens" => 15
             }
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

  describe "build_response/1" do
    test "builds Response struct from accumulated state" do
      acc = %{content: "Hello world", usage: %{"total_tokens" => 10}, finished: true}
      response = Stream.build_response(acc)
      assert %Response{content: "Hello world", usage: %{"total_tokens" => 10}} = response
    end

    test "handles nil usage" do
      acc = %{content: "test", usage: nil, finished: true}
      response = Stream.build_response(acc)
      assert %Response{content: "test", usage: %{}} = response
    end
  end
end
