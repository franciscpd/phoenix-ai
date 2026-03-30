defmodule PhoenixAI.Providers.OpenAIStreamTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Providers.OpenAI
  alias PhoenixAI.StreamChunk

  describe "parse_chunk/1" do
    test "extracts delta content from SSE data" do
      chunk =
        OpenAI.parse_chunk(%{
          event: nil,
          data:
            ~s({"choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]})
        })

      assert %StreamChunk{delta: "Hello", finish_reason: nil} = chunk
    end

    test "handles [DONE] sentinel" do
      chunk = OpenAI.parse_chunk(%{event: nil, data: "[DONE]"})
      assert %StreamChunk{finish_reason: "stop"} = chunk
    end

    test "extracts finish_reason from final chunk" do
      chunk =
        OpenAI.parse_chunk(%{
          event: nil,
          data:
            ~s({"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]})
        })

      assert %StreamChunk{delta: nil, finish_reason: "stop"} = chunk
    end

    test "handles chunk with nil content delta" do
      chunk =
        OpenAI.parse_chunk(%{
          event: nil,
          data:
            ~s({"choices":[{"index":0,"delta":{"role":"assistant"},"finish_reason":null}]})
        })

      assert %StreamChunk{delta: nil, finish_reason: nil} = chunk
    end

    test "extracts usage from chunk with usage field" do
      chunk =
        OpenAI.parse_chunk(%{
          event: nil,
          data:
            ~s({"choices":[],"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}})
        })

      assert %StreamChunk{usage: %{"prompt_tokens" => 10, "completion_tokens" => 5}} = chunk
    end
  end

  describe "build_stream_body/3" do
    test "adds stream: true and stream_options to body" do
      body =
        OpenAI.build_stream_body("gpt-4o", [%{"role" => "user", "content" => "Hi"}], [])

      assert body["stream"] == true
      assert body["stream_options"] == %{"include_usage" => true}
      assert body["model"] == "gpt-4o"
    end

    test "preserves tools and temperature from opts" do
      opts = [tools_json: [%{"type" => "function"}], temperature: 0.5]
      body = OpenAI.build_stream_body("gpt-4o", [], opts)
      assert body["stream"] == true
      assert body["tools"] == [%{"type" => "function"}]
      assert body["temperature"] == 0.5
    end
  end

  describe "stream_url/1" do
    test "returns chat completions URL with default base" do
      assert OpenAI.stream_url([]) == "https://api.openai.com/v1/chat/completions"
    end

    test "uses custom base_url from opts" do
      assert OpenAI.stream_url(base_url: "https://custom.api.com") ==
               "https://custom.api.com/chat/completions"
    end
  end

  describe "stream_headers/1" do
    test "returns authorization and content-type headers" do
      headers = OpenAI.stream_headers(api_key: "sk-test")
      assert {"authorization", "Bearer sk-test"} in headers
      assert {"content-type", "application/json"} in headers
    end
  end
end
