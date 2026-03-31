defmodule PhoenixAI.Providers.OpenAIStreamToolsTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Providers.OpenAI
  alias PhoenixAI.StreamChunk

  describe "parse_chunk/1 with tool call deltas" do
    test "extracts tool call delta with name and id from first chunk" do
      data =
        Jason.encode!(%{
          "choices" => [
            %{
              "index" => 0,
              "delta" => %{
                "tool_calls" => [
                  %{
                    "index" => 0,
                    "id" => "call_abc123",
                    "function" => %{"name" => "get_weather", "arguments" => ""}
                  }
                ]
              },
              "finish_reason" => nil
            }
          ]
        })

      chunk = OpenAI.parse_chunk(%{data: data})

      assert %StreamChunk{
               tool_call_delta: %{
                 index: 0,
                 id: "call_abc123",
                 name: "get_weather",
                 arguments: ""
               }
             } = chunk

      assert chunk.delta == nil
    end

    test "extracts tool call delta with argument fragment" do
      data =
        Jason.encode!(%{
          "choices" => [
            %{
              "index" => 0,
              "delta" => %{
                "tool_calls" => [
                  %{"index" => 0, "function" => %{"arguments" => "{\"ci"}}
                ]
              },
              "finish_reason" => nil
            }
          ]
        })

      chunk = OpenAI.parse_chunk(%{data: data})

      assert %StreamChunk{
               tool_call_delta: %{index: 0, id: nil, name: nil, arguments: "{\"ci"}
             } = chunk
    end

    test "extracts parallel tool call deltas by index" do
      data =
        Jason.encode!(%{
          "choices" => [
            %{
              "index" => 0,
              "delta" => %{
                "tool_calls" => [
                  %{
                    "index" => 1,
                    "id" => "call_def456",
                    "function" => %{"name" => "get_time", "arguments" => ""}
                  }
                ]
              },
              "finish_reason" => nil
            }
          ]
        })

      chunk = OpenAI.parse_chunk(%{data: data})

      assert %StreamChunk{tool_call_delta: %{index: 1, id: "call_def456", name: "get_time"}} =
               chunk
    end

    test "text-only chunks still work (no tool_calls key)" do
      data =
        Jason.encode!(%{
          "choices" => [
            %{"index" => 0, "delta" => %{"content" => "Hello"}, "finish_reason" => nil}
          ]
        })

      chunk = OpenAI.parse_chunk(%{data: data})
      assert %StreamChunk{delta: "Hello", tool_call_delta: nil} = chunk
    end
  end
end
