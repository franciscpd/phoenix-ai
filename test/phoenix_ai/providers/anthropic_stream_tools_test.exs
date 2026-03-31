defmodule PhoenixAI.Providers.AnthropicStreamToolsTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Providers.Anthropic
  alias PhoenixAI.StreamChunk

  describe "parse_chunk/1 with tool call deltas" do
    test "extracts tool_use from content_block_start event" do
      data =
        Jason.encode!(%{
          "type" => "content_block_start",
          "index" => 1,
          "content_block" => %{
            "type" => "tool_use",
            "id" => "toolu_abc123",
            "name" => "get_weather",
            "input" => %{}
          }
        })

      chunk = Anthropic.parse_chunk(%{event: "content_block_start", data: data})

      assert %StreamChunk{
               tool_call_delta: %{
                 index: 1,
                 id: "toolu_abc123",
                 name: "get_weather",
                 arguments: ""
               }
             } = chunk

      assert chunk.delta == nil
    end

    test "extracts input_json_delta from content_block_delta event" do
      data =
        Jason.encode!(%{
          "type" => "content_block_delta",
          "index" => 1,
          "delta" => %{
            "type" => "input_json_delta",
            "partial_json" => "{\"city\": \"San"
          }
        })

      chunk = Anthropic.parse_chunk(%{event: "content_block_delta", data: data})

      assert %StreamChunk{
               tool_call_delta: %{index: 1, arguments: "{\"city\": \"San"}
             } = chunk
    end

    test "text content_block_start returns nil (no tool_call_delta)" do
      data =
        Jason.encode!(%{
          "type" => "content_block_start",
          "index" => 0,
          "content_block" => %{"type" => "text", "text" => ""}
        })

      chunk = Anthropic.parse_chunk(%{event: "content_block_start", data: data})
      assert chunk == nil
    end

    test "text content_block_delta still extracts text delta" do
      data =
        Jason.encode!(%{
          "type" => "content_block_delta",
          "index" => 0,
          "delta" => %{"type" => "text_delta", "text" => "Hello"}
        })

      chunk = Anthropic.parse_chunk(%{event: "content_block_delta", data: data})
      assert %StreamChunk{delta: "Hello", tool_call_delta: nil} = chunk
    end

    test "content_block_stop for tool_use index returns nil" do
      data = Jason.encode!(%{"type" => "content_block_stop", "index" => 1})
      chunk = Anthropic.parse_chunk(%{event: "content_block_stop", data: data})
      assert chunk == nil
    end
  end
end
