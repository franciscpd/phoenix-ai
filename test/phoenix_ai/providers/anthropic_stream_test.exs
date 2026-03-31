defmodule PhoenixAI.Providers.AnthropicStreamTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Providers.Anthropic
  alias PhoenixAI.StreamChunk

  describe "parse_chunk/1" do
    test "extracts text delta from content_block_delta event" do
      chunk =
        Anthropic.parse_chunk(%{
          event: "content_block_delta",
          data:
            ~s({"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}})
        })

      assert %StreamChunk{delta: "Hello", finish_reason: nil} = chunk
    end

    test "extracts finish_reason from message_delta event" do
      chunk =
        Anthropic.parse_chunk(%{
          event: "message_delta",
          data:
            ~s({"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":15}})
        })

      assert %StreamChunk{finish_reason: "end_turn", delta: nil} = chunk
    end

    test "extracts usage from message_delta event" do
      chunk =
        Anthropic.parse_chunk(%{
          event: "message_delta",
          data:
            ~s({"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":15}})
        })

      assert %StreamChunk{usage: %{"output_tokens" => 15}} = chunk
    end

    test "handles message_stop as finish signal" do
      chunk = Anthropic.parse_chunk(%{event: "message_stop", data: ""})
      assert %StreamChunk{finish_reason: "stop"} = chunk
    end

    test "returns nil for ping event" do
      assert Anthropic.parse_chunk(%{event: "ping", data: ""}) == nil
    end

    test "returns nil for message_start event" do
      data =
        ~s({"type":"message_start","message":{"id":"msg_1","model":"claude-sonnet-4-5","usage":{"input_tokens":10}}})

      assert Anthropic.parse_chunk(%{event: "message_start", data: data}) == nil
    end

    test "returns nil for content_block_start event" do
      data =
        ~s({"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}})

      assert Anthropic.parse_chunk(%{event: "content_block_start", data: data}) == nil
    end

    test "returns nil for content_block_stop event" do
      assert Anthropic.parse_chunk(%{
               event: "content_block_stop",
               data: ~s({"type":"content_block_stop","index":0})
             }) == nil
    end
  end

  describe "build_stream_body/4" do
    test "adds stream: true to body" do
      body =
        Anthropic.build_stream_body(
          "claude-sonnet-4-5",
          [%{"role" => "user", "content" => "Hi"}],
          4096,
          []
        )

      assert body["stream"] == true
      assert body["model"] == "claude-sonnet-4-5"
      assert body["max_tokens"] == 4096
    end

    test "preserves existing body fields" do
      body =
        Anthropic.build_stream_body(
          "claude-sonnet-4-5",
          [%{"role" => "user", "content" => "Hi"}],
          8192,
          temperature: 0.7
        )

      assert body["stream"] == true
      assert body["temperature"] == 0.7
      assert body["max_tokens"] == 8192
    end
  end

  describe "stream_url/1" do
    test "returns messages URL with default base" do
      assert Anthropic.stream_url([]) == "https://api.anthropic.com/v1/messages"
    end

    test "uses custom base_url from opts" do
      assert Anthropic.stream_url(base_url: "https://custom.api.com") ==
               "https://custom.api.com/messages"
    end
  end

  describe "stream_headers/1" do
    test "returns x-api-key, anthropic-version, and content-type headers" do
      headers = Anthropic.stream_headers(api_key: "sk-ant-test")
      assert {"x-api-key", "sk-ant-test"} in headers
      assert {"anthropic-version", "2023-06-01"} in headers
      assert {"content-type", "application/json"} in headers
    end

    test "uses custom anthropic-version from provider_options" do
      headers =
        Anthropic.stream_headers(
          api_key: "sk-ant-test",
          provider_options: %{"anthropic-version" => "2024-01-01"}
        )

      assert {"anthropic-version", "2024-01-01"} in headers
    end
  end
end
