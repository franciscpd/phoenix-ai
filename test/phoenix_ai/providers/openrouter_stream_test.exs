defmodule PhoenixAI.Providers.OpenRouterStreamTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Providers.OpenRouter
  alias PhoenixAI.StreamChunk

  describe "parse_chunk/1 delegates to OpenAI" do
    test "extracts delta content" do
      chunk =
        OpenRouter.parse_chunk(%{
          event: nil,
          data: ~s({"choices":[{"index":0,"delta":{"content":"Hi"},"finish_reason":null}]})
        })

      assert %StreamChunk{delta: "Hi", finish_reason: nil} = chunk
    end

    test "handles [DONE] sentinel" do
      chunk = OpenRouter.parse_chunk(%{event: nil, data: "[DONE]"})
      assert %StreamChunk{finish_reason: "stop"} = chunk
    end
  end

  describe "build_stream_body/3" do
    test "adds stream: true and stream_options" do
      body =
        OpenRouter.build_stream_body(
          "mistralai/mistral-7b",
          [%{"role" => "user", "content" => "Hi"}],
          []
        )

      assert body["stream"] == true
      assert body["stream_options"] == %{"include_usage" => true}
      assert body["model"] == "mistralai/mistral-7b"
    end
  end

  describe "stream_url/1" do
    test "returns chat completions URL with default base" do
      assert OpenRouter.stream_url([]) == "https://openrouter.ai/api/v1/chat/completions"
    end
  end

  describe "stream_headers/1" do
    test "returns authorization and content-type headers" do
      headers = OpenRouter.stream_headers(api_key: "sk-or-test")
      assert {"authorization", "Bearer sk-or-test"} in headers
      assert {"content-type", "application/json"} in headers
    end
  end
end
