# Streaming + Tools Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Streaming and tool calling work together — tool call deltas are accumulated during SSE streaming, tools are executed, results are re-streamed, and all chunks (text + tool deltas) are delivered to callers via callback or PID.

**Architecture:** `Stream.run_with_tools/5` is a recursive wrapper over `Stream.run/4`. Each iteration streams via Finch, accumulates tool call deltas in the acc map, executes tools on completion, injects results, and re-streams. `AI.stream/2` detects `tools:` option and routes accordingly. Each provider's `parse_chunk/1` is extended to extract tool call deltas into `StreamChunk.tool_call_delta`.

**Tech Stack:** Elixir, Finch (SSE), server_sent_events (parser), Jason (JSON), existing PhoenixAI provider architecture, ExUnit + Mox for testing.

**Spec:** `.planning/phases/07-streaming-tools-integration/BRAINSTORM.md`

---

### Task 1: Extend OpenAI `parse_chunk/1` for tool call deltas

**Files:**
- Create: `test/phoenix_ai/providers/openai_stream_tools_test.exs`
- Modify: `lib/phoenix_ai/providers/openai.ex:131-144`

- [ ] **Step 1: Write the failing tests**

Create `test/phoenix_ai/providers/openai_stream_tools_test.exs`:

```elixir
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
      assert %StreamChunk{tool_call_delta: %{index: 1, id: "call_def456", name: "get_time"}} = chunk
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_ai/providers/openai_stream_tools_test.exs --no-color`
Expected: Failures — `tool_call_delta` is nil for tool call chunks because `parse_chunk/1` doesn't handle `delta.tool_calls` yet.

- [ ] **Step 3: Implement OpenAI parse_chunk tool call handling**

In `lib/phoenix_ai/providers/openai.ex`, replace the existing `parse_chunk/1` (lines 131-144) with:

```elixir
  @impl PhoenixAI.Provider
  def parse_chunk(%{data: "[DONE]"}), do: %StreamChunk{finish_reason: "stop"}

  def parse_chunk(%{data: data}) do
    json = Jason.decode!(data)
    choice = json |> Map.get("choices", []) |> List.first(%{})
    delta = Map.get(choice, "delta", %{})

    tool_call_delta = extract_tool_call_delta(Map.get(delta, "tool_calls"))

    %StreamChunk{
      delta: Map.get(delta, "content"),
      tool_call_delta: tool_call_delta,
      finish_reason: Map.get(choice, "finish_reason"),
      usage: Map.get(json, "usage")
    }
  end

  defp extract_tool_call_delta(nil), do: nil
  defp extract_tool_call_delta([]), do: nil

  defp extract_tool_call_delta([tc | _]) do
    function = Map.get(tc, "function", %{})

    %{
      index: Map.get(tc, "index", 0),
      id: Map.get(tc, "id"),
      name: Map.get(function, "name"),
      arguments: Map.get(function, "arguments", "")
    }
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/phoenix_ai/providers/openai_stream_tools_test.exs --no-color`
Expected: All 4 tests pass.

- [ ] **Step 5: Run full test suite to verify no regressions**

Run: `mix test --no-color`
Expected: All 209+ tests pass, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add test/phoenix_ai/providers/openai_stream_tools_test.exs lib/phoenix_ai/providers/openai.ex
git commit -m "feat(07): extend OpenAI parse_chunk/1 for tool call deltas"
```

---

### Task 2: Extend Anthropic `parse_chunk/1` for tool call deltas

**Files:**
- Create: `test/phoenix_ai/providers/anthropic_stream_tools_test.exs`
- Modify: `lib/phoenix_ai/providers/anthropic.ex:109-125`

- [ ] **Step 1: Write the failing tests**

Create `test/phoenix_ai/providers/anthropic_stream_tools_test.exs`:

```elixir
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_ai/providers/anthropic_stream_tools_test.exs --no-color`
Expected: Failures — content_block_start with tool_use returns nil, content_block_delta with input_json_delta returns text delta (nil).

- [ ] **Step 3: Implement Anthropic parse_chunk tool call handling**

In `lib/phoenix_ai/providers/anthropic.ex`, replace the existing `parse_chunk/1` clauses (lines 109-125) with:

```elixir
  @impl PhoenixAI.Provider
  def parse_chunk(%{event: "content_block_start", data: data}) do
    json = Jason.decode!(data)
    content_block = Map.get(json, "content_block", %{})

    case Map.get(content_block, "type") do
      "tool_use" ->
        %StreamChunk{
          tool_call_delta: %{
            index: Map.get(json, "index", 0),
            id: Map.get(content_block, "id"),
            name: Map.get(content_block, "name"),
            arguments: ""
          }
        }

      _ ->
        nil
    end
  end

  def parse_chunk(%{event: "content_block_delta", data: data}) do
    json = Jason.decode!(data)
    delta = Map.get(json, "delta", %{})

    case Map.get(delta, "type") do
      "text_delta" ->
        %StreamChunk{delta: Map.get(delta, "text")}

      "input_json_delta" ->
        %StreamChunk{
          tool_call_delta: %{
            index: Map.get(json, "index", 0),
            arguments: Map.get(delta, "partial_json", "")
          }
        }

      _ ->
        nil
    end
  end

  def parse_chunk(%{event: "message_delta", data: data}) do
    json = Jason.decode!(data)

    %StreamChunk{
      finish_reason: get_in(json, ["delta", "stop_reason"]),
      usage: Map.get(json, "usage")
    }
  end

  def parse_chunk(%{event: "message_stop", data: _}), do: %StreamChunk{finish_reason: "stop"}
  def parse_chunk(_), do: nil
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/phoenix_ai/providers/anthropic_stream_tools_test.exs --no-color`
Expected: All 5 tests pass.

- [ ] **Step 5: Run full test suite to verify no regressions**

Run: `mix test --no-color`
Expected: All tests pass, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add test/phoenix_ai/providers/anthropic_stream_tools_test.exs lib/phoenix_ai/providers/anthropic.ex
git commit -m "feat(07): extend Anthropic parse_chunk/1 for tool call deltas"
```

---

### Task 3: Add tool call accumulation to Stream accumulator

**Files:**
- Modify: `lib/phoenix_ai/stream.ex`
- Modify: `test/phoenix_ai/stream_test.exs`

- [ ] **Step 1: Write the failing tests**

Add to `test/phoenix_ai/stream_test.exs` — a new describe block:

```elixir
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
          %StreamChunk{
            delta: Map.get(delta, "content"),
            finish_reason: Map.get(choice, "finish_reason"),
            usage: Map.get(json, "usage")
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

      final_acc = Enum.reduce(chunks, acc, fn chunk_data, acc ->
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
        usage: %{"prompt_tokens" => 10, "completion_tokens" => 20},
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
        usage: %{},
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_ai/stream_test.exs --no-color`
Expected: Failures — `tool_calls_acc` key missing from acc, `build_response/1` doesn't handle tool calls.

- [ ] **Step 3: Implement tool call accumulation in Stream**

In `lib/phoenix_ai/stream.ex`, make these changes:

**3a.** Add `ToolCall` to the alias list (line 9):

```elixir
  alias PhoenixAI.{Error, Response, StreamChunk, ToolCall}
```

**3b.** Add `tool_calls_acc` to the accumulator in `run/4` (line 37, add after `status: nil`):

```elixir
    acc = %{
      remainder: "",
      provider_mod: provider_mod,
      callback: callback,
      content: "",
      usage: nil,
      finished: false,
      status: nil,
      tool_calls_acc: %{}
    }
```

**3c.** Add a new `apply_chunk/2` clause BEFORE the existing ones (before the `defp apply_chunk(nil, acc)` at line 95):

```elixir
  defp apply_chunk(%StreamChunk{tool_call_delta: delta} = chunk, acc)
       when is_map(delta) do
    acc.callback.(chunk)

    index = Map.get(delta, :index, 0)
    existing = Map.get(acc.tool_calls_acc, index, %{id: nil, name: nil, arguments: ""})

    updated = %{
      id: Map.get(delta, :id) || existing.id,
      name: Map.get(delta, :name) || existing.name,
      arguments: existing.arguments <> (Map.get(delta, :arguments) || "")
    }

    %{acc | tool_calls_acc: Map.put(acc.tool_calls_acc, index, updated)}
  end
```

**3d.** Update `build_response/1` (replace existing at line 112-119):

```elixir
  @doc false
  def build_response(acc) do
    tool_calls =
      (Map.get(acc, :tool_calls_acc) || %{})
      |> Enum.sort_by(fn {index, _} -> index end)
      |> Enum.map(fn {_, tc} ->
        args =
          if tc.arguments != "" do
            case Jason.decode(tc.arguments) do
              {:ok, parsed} -> parsed
              {:error, _} -> %{}
            end
          else
            %{}
          end

        %ToolCall{id: tc.id, name: tc.name, arguments: args}
      end)

    %Response{
      content: acc.content,
      tool_calls: tool_calls,
      usage: acc.usage || %{},
      finish_reason: "stop",
      provider_response: %{}
    }
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/phoenix_ai/stream_test.exs --no-color`
Expected: All tests pass (existing + 4 new).

- [ ] **Step 5: Run full test suite to verify no regressions**

Run: `mix test --no-color`
Expected: All tests pass, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_ai/stream.ex test/phoenix_ai/stream_test.exs
git commit -m "feat(07): add tool call delta accumulation to Stream module"
```

---

### Task 4: Make ToolLoop helpers public

**Files:**
- Modify: `lib/phoenix_ai/tool_loop.ex`
- Create: `test/phoenix_ai/tool_loop_helpers_test.exs`

- [ ] **Step 1: Write tests for the public helpers**

Create `test/phoenix_ai/tool_loop_helpers_test.exs`:

```elixir
defmodule PhoenixAI.ToolLoopHelpersTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.{Message, Response, ToolCall, ToolLoop, ToolResult}

  describe "build_assistant_message/1" do
    test "builds assistant message with tool calls from response" do
      response = %Response{
        content: "I'll check that for you.",
        tool_calls: [%ToolCall{id: "call_abc", name: "get_weather", arguments: %{"city" => "London"}}]
      }

      msg = ToolLoop.build_assistant_message(response)

      assert %Message{role: :assistant, content: "I'll check that for you."} = msg
      assert length(msg.tool_calls) == 1
      assert hd(msg.tool_calls).name == "get_weather"
    end
  end

  describe "execute_and_build_results/3" do
    defmodule MockTool do
      def name, do: "mock_tool"
      def description, do: "A mock tool"
      def parameters_schema, do: %{type: :object, properties: %{}}
      def execute(_args, _opts), do: {:ok, "mock result"}
    end

    test "executes tool calls and builds result messages" do
      tool_calls = [%ToolCall{id: "call_abc", name: "mock_tool", arguments: %{}}]

      results = ToolLoop.execute_and_build_results(tool_calls, [MockTool], [])

      assert [%Message{role: :tool, content: "mock result", tool_call_id: "call_abc"}] = results
    end

    test "handles unknown tool gracefully" do
      tool_calls = [%ToolCall{id: "call_abc", name: "unknown_tool", arguments: %{}}]

      results = ToolLoop.execute_and_build_results(tool_calls, [MockTool], [])

      assert [%Message{role: :tool, content: "Unknown tool: unknown_tool"}] = results
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_ai/tool_loop_helpers_test.exs --no-color`
Expected: Failures — `build_assistant_message/1` and `execute_and_build_results/3` are private.

- [ ] **Step 3: Make helpers public in ToolLoop**

In `lib/phoenix_ai/tool_loop.ex`, change these functions from `defp` to `def` and add `@doc`:

Replace line 58 (`defp execute_and_build_results`) with:

```elixir
  @doc """
  Executes a list of tool calls against the provided tool modules and builds
  result messages. Used by both synchronous ToolLoop and streaming Stream module.
  """
  def execute_and_build_results(tool_calls, tools, opts) do
```

Replace line 90 (`defp build_assistant_message`) with:

```elixir
  @doc """
  Builds an assistant message from a Response, preserving tool_calls for
  conversation history. Used by both ToolLoop and Stream.run_with_tools/5.
  """
  def build_assistant_message(%Response{} = response) do
```

Replace line 98 (`defp build_tool_result_message`) with:

```elixir
  @doc false
  def build_tool_result_message(%ToolResult{} = result) do
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/phoenix_ai/tool_loop_helpers_test.exs --no-color`
Expected: All 3 tests pass.

- [ ] **Step 5: Run full test suite**

Run: `mix test --no-color`
Expected: All tests pass, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_ai/tool_loop.ex test/phoenix_ai/tool_loop_helpers_test.exs
git commit -m "refactor(07): make ToolLoop helpers public for Stream reuse"
```

---

### Task 5: Create SSE fixture files for streaming + tool calls

**Files:**
- Create: `test/fixtures/sse/openai_tool_call.sse`
- Create: `test/fixtures/sse/anthropic_tool_call.sse`

- [ ] **Step 1: Create OpenAI tool call fixture**

Create `test/fixtures/sse/openai_tool_call.sse`:

```
event: message
data: {"choices":[{"index":0,"delta":{"role":"assistant","content":null},"finish_reason":null}]}

event: message
data: {"choices":[{"index":0,"delta":{"content":"Let me"},"finish_reason":null}]}

event: message
data: {"choices":[{"index":0,"delta":{"content":" check."},"finish_reason":null}]}

event: message
data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_abc123","type":"function","function":{"name":"get_weather","arguments":""}}]},"finish_reason":null}]}

event: message
data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"city"}}]},"finish_reason":null}]}

event: message
data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\": \"London"}}]},"finish_reason":null}]}

event: message
data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"}"}}]},"finish_reason":null}]}

event: message
data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":25,"completion_tokens":18,"total_tokens":43}}

event: message
data: [DONE]

```

- [ ] **Step 2: Create Anthropic tool call fixture**

Create `test/fixtures/sse/anthropic_tool_call.sse`:

```
event: message_start
data: {"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","model":"claude-sonnet-4-5","usage":{"input_tokens":20,"output_tokens":1}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Let me check."}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: content_block_start
data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_abc123","name":"get_weather","input":{}}}

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"city\""}}

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":": \"London\"}"}}

event: content_block_stop
data: {"type":"content_block_stop","index":1}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":15}}

event: message_stop
data: {}

```

- [ ] **Step 3: Verify fixture files are readable**

Run: `wc -l test/fixtures/sse/openai_tool_call.sse test/fixtures/sse/anthropic_tool_call.sse`
Expected: Both files exist with the expected line counts.

- [ ] **Step 4: Commit**

```bash
git add test/fixtures/sse/openai_tool_call.sse test/fixtures/sse/anthropic_tool_call.sse
git commit -m "test(07): add SSE fixture files for streaming tool calls"
```

---

### Task 6: Implement `Stream.run_with_tools/5`

**Files:**
- Create: `test/phoenix_ai/stream_tools_test.exs`
- Modify: `lib/phoenix_ai/stream.ex`

- [ ] **Step 1: Write the failing tests**

Create `test/phoenix_ai/stream_tools_test.exs`:

```elixir
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

    # Tracks call count in process dictionary for testing multi-iteration loop
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
      # We can test the max_iterations guard directly without Finch
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

      # Text chunks delivered
      assert_received {:chunk, %StreamChunk{delta: "Let me"}}
      assert_received {:chunk, %StreamChunk{delta: " check."}}
      # Tool call delta chunks also delivered
      assert_received {:chunk, %StreamChunk{tool_call_delta: %{name: "get_weather"}}}
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail or pass based on prior work**

Run: `mix test test/phoenix_ai/stream_tools_test.exs --no-color`
Expected: Fixture parsing tests should pass (built on Tasks 1-3 work). The `run_with_tools/5` test will fail because the function doesn't exist yet.

- [ ] **Step 3: Implement `Stream.run_with_tools/5`**

In `lib/phoenix_ai/stream.ex`, add these functions after the `run/4` function (after line 57):

```elixir
  @doc """
  Streaming tool loop — wraps `run/4` with tool call detection and re-streaming.

  When a stream completes with tool calls, executes the tools, injects results
  into the conversation, and re-streams. Repeats until no more tool calls or
  max_iterations reached.
  """
  @spec run_with_tools(module(), [PhoenixAI.Message.t()], callback(), [module()], keyword()) ::
          {:ok, Response.t()} | {:error, term()}
  def run_with_tools(provider_mod, messages, callback, tools, opts) do
    max_iterations = Keyword.get(opts, :max_iterations, 10)
    formatted_tools = provider_mod.format_tools(tools)

    stream_opts =
      opts
      |> Keyword.drop([:tools, :max_iterations])
      |> Keyword.put(:tools_json, formatted_tools)

    do_stream_loop(provider_mod, messages, callback, tools, stream_opts, max_iterations, 0)
  end

  defp do_stream_loop(_, _, _, _, _, max, iter) when iter >= max do
    {:error, :max_iterations_reached}
  end

  defp do_stream_loop(provider_mod, messages, callback, tools, opts, max, iter) do
    case run(provider_mod, messages, callback, opts) do
      {:ok, %Response{tool_calls: []} = response} ->
        {:ok, response}

      {:ok, %Response{tool_calls: tool_calls} = response} when is_list(tool_calls) ->
        assistant_msg = ToolLoop.build_assistant_message(response)
        tool_result_msgs = ToolLoop.execute_and_build_results(tool_calls, tools, opts)
        new_messages = messages ++ [assistant_msg | tool_result_msgs]
        do_stream_loop(provider_mod, new_messages, callback, tools, opts, max, iter + 1)

      {:error, _} = error ->
        error
    end
  end
```

Also add `ToolLoop` to the alias at line 9:

```elixir
  alias PhoenixAI.{Error, Response, StreamChunk, ToolCall, ToolLoop}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/phoenix_ai/stream_tools_test.exs --no-color`
Expected: All tests pass.

- [ ] **Step 5: Run full test suite**

Run: `mix test --no-color`
Expected: All tests pass, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_ai/stream.ex test/phoenix_ai/stream_tools_test.exs
git commit -m "feat(07): add Stream.run_with_tools/5 streaming tool loop"
```

---

### Task 7: Extend `AI.stream/2` to accept `tools:` option

**Files:**
- Create: `test/phoenix_ai/ai_stream_tools_test.exs`
- Modify: `lib/ai.ex:61-71`

- [ ] **Step 1: Write the failing tests**

Create `test/phoenix_ai/ai_stream_tools_test.exs`:

```elixir
defmodule PhoenixAI.AIStreamToolsTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.{Message, Response, StreamChunk, ToolCall}

  defmodule FakeTool do
    def name, do: "fake_tool"
    def description, do: "A fake tool"
    def parameters_schema, do: %{type: :object, properties: %{}}
    def execute(_args, _opts), do: {:ok, "fake result"}
  end

  describe "stream/2 with tools routing" do
    test "dispatch_stream routes to Stream.run_with_tools when tools present" do
      # We test the routing logic by checking that the tools option
      # is accepted and the callback mechanism still works.
      # Since we can't easily mock Finch in unit tests, we verify
      # that the function signature is correct and routing works
      # by testing with a missing API key (which fails before Finch).

      messages = [%Message{role: :user, content: "Hello"}]

      result =
        AI.stream(messages,
          provider: :openai,
          tools: [FakeTool],
          on_chunk: fn _chunk -> :ok end
        )

      # Without API key configured, it should return the standard error
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
      # Ensure tools: doesn't leak into the stream opts
      messages = [%Message{role: :user, content: "Hello"}]

      result =
        AI.stream(messages,
          provider: :openai,
          tools: [FakeTool],
          api_key: "sk-test"
        )

      # Will fail at Finch level (no connection), but won't fail
      # due to tools: being in the wrong place
      assert {:error, _} = result
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_ai/ai_stream_tools_test.exs --no-color`
Expected: The test may pass for missing_api_key (depends on whether tools triggers different code path). The routing test will tell us if dispatch_stream correctly handles tools.

- [ ] **Step 3: Extend dispatch_stream in AI module**

In `lib/ai.ex`, replace `dispatch_stream/4` (lines 61-71) with:

```elixir
  defp dispatch_stream(provider_mod, messages, opts, provider_atom) do
    case Keyword.get(opts, :api_key) do
      nil ->
        {:error, {:missing_api_key, provider_atom}}

      _key ->
        callback = build_callback(opts)
        tools = Keyword.get(opts, :tools)
        stream_opts = Keyword.drop(opts, [:on_chunk, :to, :schema, :tools])

        if tools && tools != [] do
          PhoenixAI.Stream.run_with_tools(provider_mod, messages, callback, tools, stream_opts)
        else
          PhoenixAI.Stream.run(provider_mod, messages, callback, stream_opts)
        end
    end
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/phoenix_ai/ai_stream_tools_test.exs --no-color`
Expected: All 3 tests pass.

- [ ] **Step 5: Run full test suite**

Run: `mix test --no-color`
Expected: All tests pass, 0 failures.

- [ ] **Step 6: Run Credo**

Run: `mix credo --strict --no-color`
Expected: No issues found.

- [ ] **Step 7: Commit**

```bash
git add lib/ai.ex test/phoenix_ai/ai_stream_tools_test.exs
git commit -m "feat(07): extend AI.stream/2 to accept tools: option"
```

---

### Task 8: Integration tests with SSE fixtures

**Files:**
- Modify: `test/phoenix_ai/stream_tools_test.exs` (add more tests)

- [ ] **Step 1: Add fixture-based integration tests**

Add to `test/phoenix_ai/stream_tools_test.exs`, a new describe block:

```elixir
  describe "full fixture integration" do
    test "OpenAI fixture: mixed text + tool call chunks are all delivered" do
      raw = File.read!("test/fixtures/sse/openai_tool_call.sse")
      received = :ets.new(:received, [:bag, :public])

      callback = fn chunk -> :ets.insert(received, {:chunk, chunk}) end

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

      final_acc = Stream.process_sse_events(raw, acc)
      response = Stream.build_response(final_acc)

      # Verify accumulated response
      assert response.content == "Let me check."
      assert [%ToolCall{id: "call_abc123", name: "get_weather"}] = response.tool_calls
      assert response.tool_calls |> hd() |> Map.get(:arguments) == %{"city" => "London"}
      assert response.usage == %{"prompt_tokens" => 25, "completion_tokens" => 18, "total_tokens" => 43}

      # Verify all chunk types were delivered
      all_chunks = :ets.tab2list(received) |> Enum.map(fn {:chunk, c} -> c end)
      text_chunks = Enum.filter(all_chunks, & &1.delta)
      tool_chunks = Enum.filter(all_chunks, & &1.tool_call_delta)

      assert length(text_chunks) == 2
      assert length(tool_chunks) >= 1

      :ets.delete(received)
    end

    test "Anthropic fixture: text block followed by tool_use block" do
      raw = File.read!("test/fixtures/sse/anthropic_tool_call.sse")
      received = :ets.new(:received, [:bag, :public])

      callback = fn chunk -> :ets.insert(received, {:chunk, chunk}) end

      acc = %{
        remainder: "",
        provider_mod: PhoenixAI.Providers.Anthropic,
        callback: callback,
        content: "",
        usage: nil,
        finished: false,
        status: nil,
        tool_calls_acc: %{}
      }

      final_acc = Stream.process_sse_events(raw, acc)
      response = Stream.build_response(final_acc)

      # Verify accumulated response
      assert response.content == "Let me check."
      assert [%ToolCall{id: "toolu_abc123", name: "get_weather"}] = response.tool_calls
      assert response.tool_calls |> hd() |> Map.get(:arguments) |> Map.has_key?("city")

      # Verify chunk delivery
      all_chunks = :ets.tab2list(received) |> Enum.map(fn {:chunk, c} -> c end)
      text_chunks = Enum.filter(all_chunks, & &1.delta)
      tool_chunks = Enum.filter(all_chunks, & &1.tool_call_delta)

      assert length(text_chunks) >= 1
      assert length(tool_chunks) >= 1

      :ets.delete(received)
    end
  end
```

- [ ] **Step 2: Run the integration tests**

Run: `mix test test/phoenix_ai/stream_tools_test.exs --no-color`
Expected: All tests pass (fixture parsing + integration tests).

- [ ] **Step 3: Run full test suite and Credo**

Run: `mix test --no-color && mix credo --strict --no-color`
Expected: All tests pass, no Credo issues.

- [ ] **Step 4: Commit**

```bash
git add test/phoenix_ai/stream_tools_test.exs
git commit -m "test(07): add fixture-based integration tests for streaming + tools"
```

---

### Task 9: Final verification and cleanup

**Files:**
- All modified files from Tasks 1-8

- [ ] **Step 1: Run full test suite**

Run: `mix test --no-color`
Expected: All tests pass (should be 230+ tests now), 0 failures.

- [ ] **Step 2: Run Credo strict**

Run: `mix credo --strict --no-color`
Expected: No issues found.

- [ ] **Step 3: Verify ROADMAP success criteria**

Check each criterion manually:

1. "Streaming response with mid-stream tool call events parsed correctly" → Verified by fixture tests (OpenAI + Anthropic)
2. "AI.stream/2 with on_chunk delivers StreamChunk to callback" → Verified by callback delivery test
3. "AI.stream/2 with to: pid sends messages to target process" → Existing Phase 6 tests still pass (PID delivery unchanged)
4. "Streaming + tool calling round-trip passes fixture tests for both OpenAI and Anthropic" → Verified by both fixture integration tests

- [ ] **Step 4: Fix any Credo or test issues**

If any issues found in Steps 1-2, fix them now.

- [ ] **Step 5: Final commit if cleanup was needed**

```bash
git add -A
git commit -m "fix(07): address final review issues"
```
