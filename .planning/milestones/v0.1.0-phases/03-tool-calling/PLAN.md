# Phase 3: Tool Calling — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add tool calling support with a Tool behaviour, per-provider format_tools/1 and tool result injection, a recursive ToolLoop, and AI.chat/2 extension with `tools:` option.

**Architecture:** Bottom-up: Tool behaviour and schema helpers first, then per-provider format_tools/1 and Anthropic tool result injection, then the ToolLoop recursive engine, then AI.chat/2 integration. Each layer is independently testable.

**Tech Stack:** Elixir, ExUnit + Mox (testing), Jason (JSON)

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `test/support/tools/weather_tool.ex` | Create | Test tool module implementing PhoenixAI.Tool |
| `lib/phoenix_ai/tool.ex` | Create | Tool behaviour + to_json_schema/1 helper |
| `test/phoenix_ai/tool_test.exs` | Create | Tool behaviour and schema conversion tests |
| `lib/phoenix_ai/providers/openai.ex` | Modify | Add format_tools/1 + tools_json in chat body |
| `lib/phoenix_ai/providers/anthropic.ex` | Modify | Add format_tools/1 + tool result format_message clauses + tools_json in chat body |
| `lib/phoenix_ai/providers/openrouter.ex` | Modify | Add format_tools/1 + tools_json in chat body |
| `test/phoenix_ai/providers/openai_test.exs` | Modify | Add format_tools/1 tests |
| `test/phoenix_ai/providers/anthropic_test.exs` | Modify | Add format_tools/1 and tool message format tests |
| `test/phoenix_ai/providers/openrouter_test.exs` | Modify | Add format_tools/1 tests |
| `lib/phoenix_ai/tool_loop.ex` | Create | Recursive tool execution loop |
| `test/phoenix_ai/tool_loop_test.exs` | Create | ToolLoop tests with Mox |
| `lib/ai.ex` | Modify | Route to ToolLoop when tools present |
| `test/phoenix_ai/ai_test.exs` | Modify | Add tools routing tests |

---

### Task 1: Test Tool Module + Tool Behaviour

**Files:**
- Create: `test/support/tools/weather_tool.ex`
- Create: `lib/phoenix_ai/tool.ex`
- Create: `test/phoenix_ai/tool_test.exs`

- [ ] **Step 1: Create test support tool module**

Create `test/support/tools/weather_tool.ex`:

```elixir
defmodule PhoenixAI.TestTools.WeatherTool do
  @behaviour PhoenixAI.Tool

  @impl true
  def name, do: "get_weather"

  @impl true
  def description, do: "Get current weather for a city"

  @impl true
  def parameters_schema do
    %{
      type: :object,
      properties: %{
        city: %{type: :string, description: "City name"},
        unit: %{type: :string, enum: ["celsius", "fahrenheit"]}
      },
      required: [:city]
    }
  end

  @impl true
  def execute(%{"city" => city}, _opts) do
    {:ok, "Sunny, 22°C in #{city}"}
  end
end
```

- [ ] **Step 2: Write Tool behaviour tests**

Create `test/phoenix_ai/tool_test.exs`:

```elixir
defmodule PhoenixAI.ToolTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Tool

  describe "name/1 and description/1" do
    test "delegates to module callbacks" do
      assert Tool.name(PhoenixAI.TestTools.WeatherTool) == "get_weather"
      assert Tool.description(PhoenixAI.TestTools.WeatherTool) == "Get current weather for a city"
    end
  end

  describe "to_json_schema/1" do
    test "converts atom keys to string keys" do
      schema = Tool.to_json_schema(PhoenixAI.TestTools.WeatherTool)

      assert schema["type"] == "object"
      assert is_map(schema["properties"])
      assert schema["properties"]["city"]["type"] == "string"
      assert schema["properties"]["city"]["description"] == "City name"
    end

    test "converts atom values to strings" do
      schema = Tool.to_json_schema(PhoenixAI.TestTools.WeatherTool)

      assert schema["type"] == "object"
      assert schema["properties"]["unit"]["type"] == "string"
    end

    test "preserves non-atom values" do
      schema = Tool.to_json_schema(PhoenixAI.TestTools.WeatherTool)

      assert schema["properties"]["unit"]["enum"] == ["celsius", "fahrenheit"]
    end

    test "converts required list of atoms to strings" do
      schema = Tool.to_json_schema(PhoenixAI.TestTools.WeatherTool)

      assert schema["required"] == ["city"]
    end

    test "handles nested properties" do
      defmodule NestedTool do
        @behaviour PhoenixAI.Tool
        def name, do: "nested"
        def description, do: "Nested test"

        def parameters_schema do
          %{
            type: :object,
            properties: %{
              address: %{
                type: :object,
                properties: %{
                  street: %{type: :string},
                  city: %{type: :string}
                }
              }
            }
          }
        end

        def execute(_, _), do: {:ok, "ok"}
      end

      schema = Tool.to_json_schema(NestedTool)
      assert schema["properties"]["address"]["type"] == "object"
      assert schema["properties"]["address"]["properties"]["street"]["type"] == "string"
    end
  end
end
```

- [ ] **Step 3: Run tests to verify they fail**

Run:
```bash
mix test test/phoenix_ai/tool_test.exs
```

Expected: Compilation error — `PhoenixAI.Tool` module not found.

- [ ] **Step 4: Implement Tool behaviour**

Create `lib/phoenix_ai/tool.ex`:

```elixir
defmodule PhoenixAI.Tool do
  @moduledoc """
  Behaviour for defining tools that AI models can call.

  Tools are plain modules implementing four callbacks. No OTP, no GenServer.

  ## Example

      defmodule MyApp.Weather do
        @behaviour PhoenixAI.Tool

        @impl true
        def name, do: "get_weather"

        @impl true
        def description, do: "Get current weather for a city"

        @impl true
        def parameters_schema do
          %{
            type: :object,
            properties: %{
              city: %{type: :string, description: "City name"}
            },
            required: [:city]
          }
        end

        @impl true
        def execute(%{"city" => city}, _opts) do
          {:ok, "Sunny, 22°C in \#{city}"}
        end
      end
  """

  @callback name() :: String.t()
  @callback description() :: String.t()
  @callback parameters_schema() :: map()
  @callback execute(args :: map(), opts :: keyword()) ::
              {:ok, String.t()} | {:error, term()}

  @doc "Returns the tool's name by calling `mod.name()`."
  @spec name(module()) :: String.t()
  def name(mod), do: mod.name()

  @doc "Returns the tool's description by calling `mod.description()`."
  @spec description(module()) :: String.t()
  def description(mod), do: mod.description()

  @doc """
  Converts a tool module's parameters schema from atom-keyed maps to
  string-keyed JSON Schema format.

  Atom keys become string keys. Atom values become string values.
  Non-atom values (strings, numbers, booleans, lists) pass through unchanged.
  """
  @spec to_json_schema(module()) :: map()
  def to_json_schema(mod) do
    mod.parameters_schema()
    |> deep_stringify()
  end

  defp deep_stringify(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {stringify_key(k), deep_stringify(v)} end)
  end

  defp deep_stringify(list) when is_list(list) do
    Enum.map(list, &deep_stringify/1)
  end

  defp deep_stringify(atom) when is_atom(atom) and not is_boolean(atom) and not is_nil(atom) do
    Atom.to_string(atom)
  end

  defp deep_stringify(other), do: other

  defp stringify_key(key) when is_atom(key), do: Atom.to_string(key)
  defp stringify_key(key), do: key
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run:
```bash
mix test test/phoenix_ai/tool_test.exs
```

Expected: All tests PASS.

- [ ] **Step 6: Run formatter and credo**

Run:
```bash
mix format && mix credo
```

- [ ] **Step 7: Commit**

```bash
git add test/support/tools/weather_tool.ex lib/phoenix_ai/tool.ex test/phoenix_ai/tool_test.exs
git commit -m "feat(03): add PhoenixAI.Tool behaviour with schema conversion"
```

---

### Task 2: format_tools/1 Per-Provider + tools_json in chat body

**Files:**
- Modify: `lib/phoenix_ai/providers/openai.ex`
- Modify: `lib/phoenix_ai/providers/anthropic.ex`
- Modify: `lib/phoenix_ai/providers/openrouter.ex`
- Modify: `test/phoenix_ai/providers/openai_test.exs`
- Modify: `test/phoenix_ai/providers/anthropic_test.exs`
- Modify: `test/phoenix_ai/providers/openrouter_test.exs`

- [ ] **Step 1: Write format_tools tests for all 3 adapters**

Add to `test/phoenix_ai/providers/openai_test.exs`, after the existing `describe "format_messages/1"` block:

```elixir
  describe "format_tools/1" do
    test "wraps tool in OpenAI function calling format" do
      [tool_def] = PhoenixAI.Providers.OpenAI.format_tools([PhoenixAI.TestTools.WeatherTool])

      assert tool_def["type"] == "function"
      assert tool_def["function"]["name"] == "get_weather"
      assert tool_def["function"]["description"] == "Get current weather for a city"
      assert tool_def["function"]["parameters"]["type"] == "object"
      assert tool_def["function"]["parameters"]["properties"]["city"]["type"] == "string"
      assert tool_def["function"]["parameters"]["required"] == ["city"]
    end
  end
```

Add to `test/phoenix_ai/providers/anthropic_test.exs`, after the existing `describe "extract_system/1"` block:

```elixir
  describe "format_tools/1" do
    test "formats tool in Anthropic tool use format" do
      [tool_def] = Anthropic.format_tools([PhoenixAI.TestTools.WeatherTool])

      assert tool_def["name"] == "get_weather"
      assert tool_def["description"] == "Get current weather for a city"
      assert tool_def["input_schema"]["type"] == "object"
      assert tool_def["input_schema"]["properties"]["city"]["type"] == "string"
      assert tool_def["input_schema"]["required"] == ["city"]
      refute Map.has_key?(tool_def, "type")
    end
  end
```

Add to `test/phoenix_ai/providers/openrouter_test.exs`, after the existing `describe "chat/2 validation"` block:

```elixir
  describe "format_tools/1" do
    test "wraps tool in OpenAI-compatible function calling format" do
      [tool_def] = OpenRouter.format_tools([PhoenixAI.TestTools.WeatherTool])

      assert tool_def["type"] == "function"
      assert tool_def["function"]["name"] == "get_weather"
      assert tool_def["function"]["description"] == "Get current weather for a city"
      assert tool_def["function"]["parameters"]["type"] == "object"
      assert tool_def["function"]["parameters"]["properties"]["city"]["type"] == "string"
      assert tool_def["function"]["parameters"]["required"] == ["city"]
    end
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
mix test test/phoenix_ai/providers/openai_test.exs test/phoenix_ai/providers/anthropic_test.exs test/phoenix_ai/providers/openrouter_test.exs
```

Expected: Errors — `format_tools/1` undefined.

- [ ] **Step 3: Implement format_tools/1 in OpenAI adapter**

Add to `lib/phoenix_ai/providers/openai.ex`, after the `parse_response/1` function and before `format_messages/1`:

```elixir
  @impl PhoenixAI.Provider
  def format_tools(tools) do
    Enum.map(tools, fn mod ->
      %{
        "type" => "function",
        "function" => %{
          "name" => PhoenixAI.Tool.name(mod),
          "description" => PhoenixAI.Tool.description(mod),
          "parameters" => PhoenixAI.Tool.to_json_schema(mod)
        }
      }
    end)
  end
```

Also add `|> maybe_put("tools", Keyword.get(opts, :tools_json))` to the body construction in `chat/2`. Change lines 21-28 from:

```elixir
    body =
      %{
        "model" => model,
        "messages" => format_messages(messages)
      }
      |> maybe_put("temperature", Keyword.get(opts, :temperature))
      |> maybe_put("max_tokens", Keyword.get(opts, :max_tokens))
      |> Map.merge(provider_options)
```

To:

```elixir
    body =
      %{
        "model" => model,
        "messages" => format_messages(messages)
      }
      |> maybe_put("tools", Keyword.get(opts, :tools_json))
      |> maybe_put("temperature", Keyword.get(opts, :temperature))
      |> maybe_put("max_tokens", Keyword.get(opts, :max_tokens))
      |> Map.merge(provider_options)
```

- [ ] **Step 4: Implement format_tools/1 in Anthropic adapter**

Add to `lib/phoenix_ai/providers/anthropic.ex`, after `parse_response/1` and before `extract_system/1`:

```elixir
  @impl PhoenixAI.Provider
  def format_tools(tools) do
    Enum.map(tools, fn mod ->
      %{
        "name" => PhoenixAI.Tool.name(mod),
        "description" => PhoenixAI.Tool.description(mod),
        "input_schema" => PhoenixAI.Tool.to_json_schema(mod)
      }
    end)
  end
```

Also add `|> maybe_put("tools", Keyword.get(opts, :tools_json))` to the body construction in `chat/2`. Change lines 35-43 from:

```elixir
    body =
      %{
        "model" => model,
        "messages" => format_messages(messages),
        "max_tokens" => Keyword.get(opts, :max_tokens, 4096)
      }
      |> maybe_put("system", system)
      |> maybe_put("temperature", Keyword.get(opts, :temperature))
      |> Map.merge(Map.drop(provider_options, ["anthropic-version"]))
```

To:

```elixir
    body =
      %{
        "model" => model,
        "messages" => format_messages(messages),
        "max_tokens" => Keyword.get(opts, :max_tokens, 4096)
      }
      |> maybe_put("system", system)
      |> maybe_put("tools", Keyword.get(opts, :tools_json))
      |> maybe_put("temperature", Keyword.get(opts, :temperature))
      |> Map.merge(Map.drop(provider_options, ["anthropic-version"]))
```

- [ ] **Step 5: Implement format_tools/1 in OpenRouter adapter**

Add to `lib/phoenix_ai/providers/openrouter.ex`, after `validate_model/1` and before `format_messages/1`:

```elixir
  @impl PhoenixAI.Provider
  def format_tools(tools) do
    Enum.map(tools, fn mod ->
      %{
        "type" => "function",
        "function" => %{
          "name" => PhoenixAI.Tool.name(mod),
          "description" => PhoenixAI.Tool.description(mod),
          "parameters" => PhoenixAI.Tool.to_json_schema(mod)
        }
      }
    end)
  end
```

Also add `|> maybe_put("tools", Keyword.get(opts, :tools_json))` to the body construction in `do_chat/2`. Change lines 73-78 from:

```elixir
    body =
      %{
        "model" => model,
        "messages" => format_messages(messages)
      }
      |> maybe_put("temperature", Keyword.get(opts, :temperature))
      |> maybe_put("max_tokens", Keyword.get(opts, :max_tokens))
```

To:

```elixir
    body =
      %{
        "model" => model,
        "messages" => format_messages(messages)
      }
      |> maybe_put("tools", Keyword.get(opts, :tools_json))
      |> maybe_put("temperature", Keyword.get(opts, :temperature))
      |> maybe_put("max_tokens", Keyword.get(opts, :max_tokens))
```

- [ ] **Step 6: Run tests**

Run:
```bash
mix test
```

Expected: All tests PASS (including new format_tools tests).

- [ ] **Step 7: Run formatter and credo**

Run:
```bash
mix format && mix credo
```

- [ ] **Step 8: Commit**

```bash
git add lib/phoenix_ai/providers/openai.ex lib/phoenix_ai/providers/anthropic.ex lib/phoenix_ai/providers/openrouter.ex test/phoenix_ai/providers/openai_test.exs test/phoenix_ai/providers/anthropic_test.exs test/phoenix_ai/providers/openrouter_test.exs
git commit -m "feat(03): add format_tools/1 to all provider adapters"
```

---

### Task 3: Anthropic Tool Result Injection

**Files:**
- Modify: `lib/phoenix_ai/providers/anthropic.ex`
- Modify: `test/phoenix_ai/providers/anthropic_test.exs`

- [ ] **Step 1: Write tests for Anthropic tool message formatting**

Add to `test/phoenix_ai/providers/anthropic_test.exs`, inside or after the `describe "format_messages/1"` block:

```elixir
  describe "format_messages/1 tool calling" do
    test "converts tool result to Anthropic tool_result content block" do
      messages = [
        %PhoenixAI.Message{role: :tool, content: "Sunny, 22°C", tool_call_id: "toolu_abc123"}
      ]

      [formatted] = Anthropic.format_messages(messages)

      assert formatted["role"] == "user"
      assert [%{"type" => "tool_result", "tool_use_id" => "toolu_abc123", "content" => "Sunny, 22°C"}] =
               formatted["content"]
    end

    test "converts assistant message with tool_calls to content blocks" do
      tc = %PhoenixAI.ToolCall{id: "toolu_abc", name: "get_weather", arguments: %{"city" => "Lisbon"}}

      messages = [
        %PhoenixAI.Message{role: :assistant, content: "Let me check.", tool_calls: [tc]}
      ]

      [formatted] = Anthropic.format_messages(messages)

      assert formatted["role"] == "assistant"
      assert [text_block, tool_block] = formatted["content"]
      assert text_block == %{"type" => "text", "text" => "Let me check."}
      assert tool_block["type"] == "tool_use"
      assert tool_block["id"] == "toolu_abc"
      assert tool_block["name"] == "get_weather"
      assert tool_block["input"] == %{"city" => "Lisbon"}
    end

    test "assistant message with tool_calls but no text content omits text block" do
      tc = %PhoenixAI.ToolCall{id: "toolu_abc", name: "get_weather", arguments: %{"city" => "Lisbon"}}

      messages = [
        %PhoenixAI.Message{role: :assistant, content: nil, tool_calls: [tc]}
      ]

      [formatted] = Anthropic.format_messages(messages)

      assert formatted["role"] == "assistant"
      assert [tool_block] = formatted["content"]
      assert tool_block["type"] == "tool_use"
    end
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
mix test test/phoenix_ai/providers/anthropic_test.exs
```

Expected: Failures — current `format_message/1` only has the generic clause.

- [ ] **Step 3: Add tool result and assistant-with-tool_calls clauses to Anthropic adapter**

In `lib/phoenix_ai/providers/anthropic.ex`, replace the single `format_message/1` clause (around line 119):

```elixir
  defp format_message(%Message{role: role, content: content}) do
    %{"role" => to_string(role), "content" => content}
  end
```

With three clauses (order matters — specific before generic):

```elixir
  defp format_message(%Message{role: :tool, content: content, tool_call_id: tool_call_id}) do
    %{
      "role" => "user",
      "content" => [
        %{
          "type" => "tool_result",
          "tool_use_id" => tool_call_id,
          "content" => content
        }
      ]
    }
  end

  defp format_message(%Message{role: :assistant, tool_calls: tool_calls} = msg)
       when is_list(tool_calls) and tool_calls != [] do
    text_blocks = if msg.content, do: [%{"type" => "text", "text" => msg.content}], else: []

    tool_blocks =
      Enum.map(tool_calls, fn tc ->
        %{"type" => "tool_use", "id" => tc.id, "name" => tc.name, "input" => tc.arguments}
      end)

    %{"role" => "assistant", "content" => text_blocks ++ tool_blocks}
  end

  defp format_message(%Message{role: role, content: content}) do
    %{"role" => to_string(role), "content" => content}
  end
```

- [ ] **Step 4: Run tests**

Run:
```bash
mix test test/phoenix_ai/providers/anthropic_test.exs
```

Expected: All tests PASS.

- [ ] **Step 5: Run formatter and credo**

Run:
```bash
mix format && mix credo
```

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_ai/providers/anthropic.ex test/phoenix_ai/providers/anthropic_test.exs
git commit -m "feat(03): add Anthropic tool result injection in format_messages"
```

---

### Task 4: ToolLoop

**Files:**
- Create: `lib/phoenix_ai/tool_loop.ex`
- Create: `test/phoenix_ai/tool_loop_test.exs`

- [ ] **Step 1: Write ToolLoop tests**

Create `test/phoenix_ai/tool_loop_test.exs`:

```elixir
defmodule PhoenixAI.ToolLoopTest do
  use ExUnit.Case, async: false

  import Mox

  alias PhoenixAI.{Message, Response, ToolCall, ToolLoop}

  setup :verify_on_exit!

  @tools [PhoenixAI.TestTools.WeatherTool]
  @base_opts [api_key: "test-key", model: "test-model"]

  describe "run/4" do
    test "single iteration: tool call → execute → final response" do
      # First call: provider returns a tool call
      PhoenixAI.MockProvider
      |> expect(:format_tools, fn tools ->
        assert tools == @tools
        [%{"type" => "function", "function" => %{"name" => "get_weather"}}]
      end)
      |> expect(:chat, fn _messages, _opts ->
        {:ok,
         %Response{
           content: nil,
           tool_calls: [%ToolCall{id: "call_1", name: "get_weather", arguments: %{"city" => "Lisbon"}}],
           finish_reason: "tool_calls"
         }}
      end)
      # Second call: provider returns final response (no tool calls)
      |> expect(:chat, fn messages, _opts ->
        # Verify tool result was injected
        tool_msg = Enum.find(messages, &(&1.role == :tool))
        assert tool_msg.content == "Sunny, 22°C in Lisbon"
        assert tool_msg.tool_call_id == "call_1"

        {:ok, %Response{content: "The weather in Lisbon is sunny!", tool_calls: [], finish_reason: "stop"}}
      end)

      messages = [%Message{role: :user, content: "What's the weather in Lisbon?"}]
      assert {:ok, %Response{content: "The weather in Lisbon is sunny!"}} =
               ToolLoop.run(PhoenixAI.MockProvider, messages, @tools, @base_opts)
    end

    test "max iterations reached" do
      PhoenixAI.MockProvider
      |> expect(:format_tools, fn _tools ->
        [%{"type" => "function", "function" => %{"name" => "get_weather"}}]
      end)
      |> expect(:chat, 3, fn _messages, _opts ->
        {:ok,
         %Response{
           content: nil,
           tool_calls: [%ToolCall{id: "call_1", name: "get_weather", arguments: %{"city" => "Lisbon"}}],
           finish_reason: "tool_calls"
         }}
      end)

      messages = [%Message{role: :user, content: "weather?"}]
      assert {:error, :max_iterations_reached} =
               ToolLoop.run(PhoenixAI.MockProvider, messages, @tools, @base_opts ++ [max_iterations: 2])
    end

    test "tool error is sent to provider as tool result" do
      defmodule FailingTool do
        @behaviour PhoenixAI.Tool
        def name, do: "failing_tool"
        def description, do: "Always fails"
        def parameters_schema, do: %{type: :object, properties: %{}}
        def execute(_, _), do: {:error, "something went wrong"}
      end

      PhoenixAI.MockProvider
      |> expect(:format_tools, fn _tools -> [%{}] end)
      |> expect(:chat, fn _messages, _opts ->
        {:ok,
         %Response{
           content: nil,
           tool_calls: [%ToolCall{id: "call_1", name: "failing_tool", arguments: %{}}],
           finish_reason: "tool_calls"
         }}
      end)
      |> expect(:chat, fn messages, _opts ->
        tool_msg = Enum.find(messages, &(&1.role == :tool))
        assert tool_msg.content == "something went wrong"
        {:ok, %Response{content: "Tool failed", tool_calls: [], finish_reason: "stop"}}
      end)

      messages = [%Message{role: :user, content: "test"}]
      assert {:ok, %Response{content: "Tool failed"}} =
               ToolLoop.run(PhoenixAI.MockProvider, messages, [FailingTool], @base_opts)
    end

    test "tool exception is caught and sent as error" do
      defmodule CrashingTool do
        @behaviour PhoenixAI.Tool
        def name, do: "crashing_tool"
        def description, do: "Always crashes"
        def parameters_schema, do: %{type: :object, properties: %{}}
        def execute(_, _), do: raise("boom!")
      end

      PhoenixAI.MockProvider
      |> expect(:format_tools, fn _tools -> [%{}] end)
      |> expect(:chat, fn _messages, _opts ->
        {:ok,
         %Response{
           content: nil,
           tool_calls: [%ToolCall{id: "call_1", name: "crashing_tool", arguments: %{}}],
           finish_reason: "tool_calls"
         }}
      end)
      |> expect(:chat, fn messages, _opts ->
        tool_msg = Enum.find(messages, &(&1.role == :tool))
        assert tool_msg.content == "boom!"
        {:ok, %Response{content: "Tool crashed", tool_calls: [], finish_reason: "stop"}}
      end)

      messages = [%Message{role: :user, content: "test"}]
      assert {:ok, %Response{content: "Tool crashed"}} =
               ToolLoop.run(PhoenixAI.MockProvider, messages, [CrashingTool], @base_opts)
    end

    test "unknown tool name sends error tool result" do
      PhoenixAI.MockProvider
      |> expect(:format_tools, fn _tools -> [%{}] end)
      |> expect(:chat, fn _messages, _opts ->
        {:ok,
         %Response{
           content: nil,
           tool_calls: [%ToolCall{id: "call_1", name: "nonexistent", arguments: %{}}],
           finish_reason: "tool_calls"
         }}
      end)
      |> expect(:chat, fn messages, _opts ->
        tool_msg = Enum.find(messages, &(&1.role == :tool))
        assert tool_msg.content =~ "Unknown tool: nonexistent"
        {:ok, %Response{content: "No such tool", tool_calls: [], finish_reason: "stop"}}
      end)

      messages = [%Message{role: :user, content: "test"}]
      assert {:ok, %Response{content: "No such tool"}} =
               ToolLoop.run(PhoenixAI.MockProvider, messages, @tools, @base_opts)
    end

    test "provider error aborts the loop" do
      PhoenixAI.MockProvider
      |> expect(:format_tools, fn _tools -> [%{}] end)
      |> expect(:chat, fn _messages, _opts ->
        {:error, %PhoenixAI.Error{status: 500, message: "Server error", provider: :mock}}
      end)

      messages = [%Message{role: :user, content: "test"}]
      assert {:error, %PhoenixAI.Error{status: 500}} =
               ToolLoop.run(PhoenixAI.MockProvider, messages, @tools, @base_opts)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
mix test test/phoenix_ai/tool_loop_test.exs
```

Expected: Compilation error — `PhoenixAI.ToolLoop` module not found.

- [ ] **Step 3: Implement ToolLoop**

Create `lib/phoenix_ai/tool_loop.ex`:

```elixir
defmodule PhoenixAI.ToolLoop do
  @moduledoc """
  Recursive tool execution loop.

  Calls the provider, detects tool calls in the response, executes the matching
  tool modules, injects results back into the conversation, and re-calls the
  provider until no more tool calls are requested.

  This is a pure functional module — no GenServer, no state, no processes.
  The Agent GenServer (Phase 4) reuses this module.
  """

  alias PhoenixAI.{Message, Response, ToolCall, ToolResult}

  @default_max_iterations 10

  @doc """
  Runs the tool calling loop.

  Returns `{:ok, %Response{}}` with the final response after all tool calls
  complete, or `{:error, reason}` on provider error or max iterations.
  """
  @spec run(module(), [Message.t()], [module()], keyword()) ::
          {:ok, Response.t()} | {:error, term()}
  def run(provider_mod, messages, tools, opts) do
    formatted_tools = provider_mod.format_tools(tools)
    max_iterations = Keyword.get(opts, :max_iterations, @default_max_iterations)
    opts_with_tools = Keyword.put(opts, :tools_json, formatted_tools)

    do_loop(provider_mod, messages, tools, opts_with_tools, max_iterations, 0)
  end

  defp do_loop(_provider_mod, _messages, _tools, _opts, max, iteration) when iteration >= max do
    {:error, :max_iterations_reached}
  end

  defp do_loop(provider_mod, messages, tools, opts, max, iteration) do
    case provider_mod.chat(messages, opts) do
      {:ok, %Response{tool_calls: []} = response} ->
        {:ok, response}

      {:ok, %Response{tool_calls: tool_calls} = response} when is_list(tool_calls) ->
        assistant_msg = build_assistant_message(response)
        tool_result_msgs = execute_and_build_results(tool_calls, tools, opts)

        new_messages = messages ++ [assistant_msg | tool_result_msgs]
        do_loop(provider_mod, new_messages, tools, opts, max, iteration + 1)

      {:error, _} = error ->
        error
    end
  end

  defp execute_and_build_results(tool_calls, tools, opts) do
    Enum.map(tool_calls, fn tc ->
      result = execute_tool(tc, tools, opts)
      build_tool_result_message(result)
    end)
  end

  defp execute_tool(%ToolCall{} = tool_call, tools, opts) do
    case find_tool(tools, tool_call.name) do
      nil ->
        %ToolResult{tool_call_id: tool_call.id, error: "Unknown tool: #{tool_call.name}"}

      mod ->
        try do
          case mod.execute(tool_call.arguments, opts) do
            {:ok, result} ->
              %ToolResult{tool_call_id: tool_call.id, content: result}

            {:error, reason} ->
              %ToolResult{tool_call_id: tool_call.id, error: to_string(reason)}
          end
        rescue
          e ->
            %ToolResult{tool_call_id: tool_call.id, error: Exception.message(e)}
        end
    end
  end

  defp find_tool(tools, name) do
    Enum.find(tools, fn mod -> mod.name() == name end)
  end

  defp build_assistant_message(%Response{} = response) do
    %Message{
      role: :assistant,
      content: response.content,
      tool_calls: response.tool_calls
    }
  end

  defp build_tool_result_message(%ToolResult{} = result) do
    %Message{
      role: :tool,
      content: result.content || result.error,
      tool_call_id: result.tool_call_id
    }
  end
end
```

- [ ] **Step 4: Run tests**

Run:
```bash
mix test test/phoenix_ai/tool_loop_test.exs
```

Expected: All tests PASS.

- [ ] **Step 5: Run full test suite**

Run:
```bash
mix test
```

Expected: All tests PASS.

- [ ] **Step 6: Run formatter and credo**

Run:
```bash
mix format && mix credo
```

- [ ] **Step 7: Commit**

```bash
git add lib/phoenix_ai/tool_loop.ex test/phoenix_ai/tool_loop_test.exs
git commit -m "feat(03): add ToolLoop recursive tool execution engine"
```

---

### Task 5: AI.chat/2 Extension + Integration Tests

**Files:**
- Modify: `lib/ai.ex`
- Modify: `test/phoenix_ai/ai_test.exs`

- [ ] **Step 1: Write AI.chat integration tests for tools routing**

Add to `test/phoenix_ai/ai_test.exs`, inside the `describe "chat/2"` block:

```elixir
    test "routes to ToolLoop when tools option is present" do
      # First call: format_tools
      PhoenixAI.MockProvider
      |> expect(:format_tools, fn tools ->
        assert [PhoenixAI.TestTools.WeatherTool] = tools
        [%{"type" => "function", "function" => %{"name" => "get_weather"}}]
      end)
      # Second call: chat returns no tool calls (immediate completion)
      |> expect(:chat, fn _messages, opts ->
        assert opts[:tools_json] != nil
        {:ok, %PhoenixAI.Response{content: "It's sunny!", tool_calls: [], finish_reason: "stop"}}
      end)

      result =
        AI.chat(
          [%PhoenixAI.Message{role: :user, content: "Weather?"}],
          provider: PhoenixAI.MockProvider,
          api_key: "test-key",
          tools: [PhoenixAI.TestTools.WeatherTool]
        )

      assert {:ok, %PhoenixAI.Response{content: "It's sunny!"}} = result
    end

    test "without tools option, does not invoke ToolLoop" do
      expect(PhoenixAI.MockProvider, :chat, fn _messages, opts ->
        refute Keyword.has_key?(opts, :tools_json)
        {:ok, %PhoenixAI.Response{content: "Hello!", tool_calls: []}}
      end)

      result =
        AI.chat(
          [%PhoenixAI.Message{role: :user, content: "Hi"}],
          provider: PhoenixAI.MockProvider,
          api_key: "test-key"
        )

      assert {:ok, %PhoenixAI.Response{content: "Hello!"}} = result
    end
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
mix test test/phoenix_ai/ai_test.exs
```

Expected: First test fails — AI.chat does not route to ToolLoop yet.

- [ ] **Step 3: Modify AI.chat/2 to route through ToolLoop when tools present**

In `lib/ai.ex`, replace the `chat/2` function:

```elixir
  @spec chat([PhoenixAI.Message.t()], keyword()) ::
          {:ok, PhoenixAI.Response.t()} | {:error, term()}
  def chat(messages, opts \\ []) do
    provider_atom = opts[:provider] || default_provider()

    case resolve_provider(provider_atom) do
      {:ok, provider_mod} ->
        merged_opts = Config.resolve(provider_atom, Keyword.delete(opts, :provider))

        case merged_opts[:api_key] do
          nil ->
            {:error, {:missing_api_key, provider_atom}}

          _key ->
            tools = Keyword.get(merged_opts, :tools)

            if tools && tools != [] do
              PhoenixAI.ToolLoop.run(provider_mod, messages, tools, merged_opts)
            else
              provider_mod.chat(messages, merged_opts)
            end
        end

      {:error, _} = error ->
        error
    end
  end
```

- [ ] **Step 4: Run full test suite**

Run:
```bash
mix test
```

Expected: All tests PASS.

- [ ] **Step 5: Run formatter and credo**

Run:
```bash
mix format && mix credo
```

- [ ] **Step 6: Commit**

```bash
git add lib/ai.ex test/phoenix_ai/ai_test.exs
git commit -m "feat(03): extend AI.chat/2 with tools option for automatic tool calling"
```

---

### Task 6: Final Verification

- [ ] **Step 1: Run full test suite with coverage**

Run:
```bash
mix test --cover
```

Expected: All tests PASS.

- [ ] **Step 2: Run all quality checks**

Run:
```bash
mix format --check-formatted && mix credo
```

Expected: Clean.

- [ ] **Step 3: Verify success criteria**

1. ✅ `PhoenixAI.Tool` behaviour exists with `name/0`, `description/0`, `parameters_schema/0`, `execute/2`
2. ✅ `to_json_schema/1` converts atom-keyed schemas to string-keyed JSON Schema
3. ✅ OpenAI `format_tools/1` wraps in `type: "function"` envelope
4. ✅ Anthropic `format_tools/1` uses `input_schema` key
5. ✅ Anthropic `format_message/1` converts `:tool` role to `role: "user"` with `tool_result` content block
6. ✅ `ToolLoop.run/4` completes the recursive call→execute→re-call loop
7. ✅ `AI.chat/2` with `tools:` routes through ToolLoop automatically
8. ✅ Tool modules are plain modules — no OTP, no GenServer

---

## Summary

| Task | Description | Commit Message |
|------|-------------|---------------|
| 1 | Tool behaviour + schema conversion + test tool | `feat(03): add PhoenixAI.Tool behaviour with schema conversion` |
| 2 | format_tools/1 all adapters + tools_json in body | `feat(03): add format_tools/1 to all provider adapters` |
| 3 | Anthropic tool result injection | `feat(03): add Anthropic tool result injection in format_messages` |
| 4 | ToolLoop recursive engine | `feat(03): add ToolLoop recursive tool execution engine` |
| 5 | AI.chat/2 extension + integration tests | `feat(03): extend AI.chat/2 with tools option for automatic tool calling` |
| 6 | Final verification | No commit — verification only |
