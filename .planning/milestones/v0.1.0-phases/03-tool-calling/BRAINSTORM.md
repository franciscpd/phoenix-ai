# Phase 3: Tool Calling — Design Spec

**Date:** 2026-03-29
**Phase:** 03-tool-calling
**Status:** Approved
**Approach:** A — Bottom-up (Tool → format_tools → injection → ToolLoop → AI.chat)

## Overview

Add tool calling support: a Tool behaviour for defining callable tools, per-provider format_tools/1 and tool result injection, a recursive ToolLoop module, and AI.chat/2 extension with `tools:` option. The round-trip works for OpenAI, Anthropic, and OpenRouter.

**Requirements covered:** TOOL-01, TOOL-02, TOOL-03, TOOL-04, TOOL-05, PROV-04

## Architecture

### Component Diagram

```
AI.chat/2 (extended with tools: option)
├── No tools → provider_mod.chat/2 (unchanged)
└── With tools:
    ├── provider_mod.format_tools(tools) → serialized tool schemas
    └── ToolLoop.run(provider_mod, messages, tools, opts)
        ├── provider_mod.chat(messages, opts_with_tools)
        ├── Response has tool_calls?
        │   ├── Yes → execute_tools → build result messages → recurse
        │   └── No → return {:ok, response}
        └── Error? → return {:error, reason}
```

### Data Flow (single loop iteration)

```
ToolLoop.run
  → provider_mod.chat(messages, opts ++ [tools_json: formatted_tools])
  → {:ok, %Response{tool_calls: [%ToolCall{name: "get_weather", args: %{"city" => "Lisbon"}}]}}
  → lookup tool module by name → MyApp.Weather
  → MyApp.Weather.execute(%{"city" => "Lisbon"}, opts)
  → {:ok, "Sunny, 22°C"}
  → build messages:
      [assistant_msg(response), tool_result_msg("Sunny, 22°C", tool_call_id)]
  → append to conversation → recurse
  → provider returns final response with tool_calls: []
  → {:ok, %Response{content: "The weather in Lisbon is sunny, 22°C"}}
```

## Components

### 1. PhoenixAI.Tool Behaviour (`lib/phoenix_ai/tool.ex`)

Defines the contract for tool modules. Plain behaviour, no `use` macro — follows the Elixir idiom of explicit `@behaviour` for simple contracts (no boilerplate to eliminate via `__using__`).

**Callbacks:**

```elixir
@callback name() :: String.t()
@callback description() :: String.t()
@callback parameters_schema() :: map()
@callback execute(args :: map(), opts :: keyword()) ::
            {:ok, String.t()} | {:error, term()}
```

**Helper functions (not callbacks):**

```elixir
# Delegates to module callbacks for convenience
def name(mod), do: mod.name()
def description(mod), do: mod.description()

# Converts atom-keyed schema to string-keyed JSON Schema
def to_json_schema(mod) do
  mod.parameters_schema()
  |> deep_stringify_keys()
end
```

**Schema format:** Plain Elixir maps with atom keys following JSON Schema structure:

```elixir
%{
  type: :object,
  properties: %{
    city: %{type: :string, description: "City name"},
    unit: %{type: :string, enum: ["celsius", "fahrenheit"]}
  },
  required: [:city]
}
```

`to_json_schema/1` converts this to:

```json
{
  "type": "object",
  "properties": {
    "city": {"type": "string", "description": "City name"},
    "unit": {"type": "string", "enum": ["celsius", "fahrenheit"]}
  },
  "required": ["city"]
}
```

**deep_stringify_keys/1** — Recursive conversion: atom keys → string keys, atom values → string values (`:string` → `"string"`, `:object` → `"object"`, `:integer` → `"integer"`, etc.). Non-atom values (strings, numbers, booleans, lists) pass through unchanged. This converts ALL atom values, not just known JSON Schema types — simpler and forward-compatible.

**Tool module example:**

```elixir
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
    {:ok, "Sunny, 22°C in #{city}"}
  end
end
```

### 2. format_tools/1 Per-Provider

Each adapter implements `format_tools/1` (already defined as `@optional_callback` in Provider behaviour). Takes a list of tool modules, returns a list of provider-formatted tool definitions.

**OpenAI adapter (`lib/phoenix_ai/providers/openai.ex`):**

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

**Anthropic adapter (`lib/phoenix_ai/providers/anthropic.ex`):**

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

**OpenRouter adapter (`lib/phoenix_ai/providers/openrouter.ex`):**

Same as OpenAI (OpenAI-compatible API). Independently implemented — no delegation.

### 3. Anthropic Tool Result Injection

The Anthropic adapter's `format_message/1` needs two new clauses for tool calling messages. These are per-provider (PROV-04) — no shared code.

**New clause — tool result message:**

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
```

**New clause — assistant message with tool calls:**

```elixir
defp format_message(%Message{role: :assistant, tool_calls: tool_calls} = msg)
     when is_list(tool_calls) and tool_calls != [] do
  text_blocks = if msg.content, do: [%{"type" => "text", "text" => msg.content}], else: []

  tool_blocks =
    Enum.map(tool_calls, fn tc ->
      %{"type" => "tool_use", "id" => tc.id, "name" => tc.name, "input" => tc.arguments}
    end)

  %{"role" => "assistant", "content" => text_blocks ++ tool_blocks}
end
```

**OpenAI and OpenRouter:** Already handle `:tool` role and assistant-with-tool_calls in their existing `format_message/1` clauses. No changes needed.

### 4. PhoenixAI.ToolLoop (`lib/phoenix_ai/tool_loop.ex`)

Pure functional module. Recursive loop: call provider → detect tool calls → execute tools → inject results → re-call → until stop.

**Public API:**

```elixir
@spec run(module(), [Message.t()], [module()], keyword()) ::
        {:ok, Response.t()} | {:error, term()}
def run(provider_mod, messages, tools, opts)
```

**Loop logic:**

1. Serialize tools: `formatted_tools = provider_mod.format_tools(tools)`
2. Call provider: `provider_mod.chat(messages, Keyword.put(opts, :tools_json, formatted_tools))`
3. Match result:
   - `{:ok, %Response{tool_calls: []}}` → return `{:ok, response}` (done)
   - `{:ok, %Response{tool_calls: [_ | _]} = response}` →
     - Build assistant message from response
     - Execute each tool call, build tool result messages
     - Append all to message history
     - Check iteration count against `max_iterations` (default 10)
     - Recurse with updated messages and incremented counter
   - `{:error, _}` → return error (abort)
4. If iteration count >= max_iterations → `{:error, :max_iterations_reached}`

**Tool execution:**

```elixir
defp execute_tool(tool_call, tools, opts) do
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
```

**Message construction between iterations:**

```elixir
defp build_assistant_message(response) do
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
```

### 5. AI.chat/2 Extension (`lib/ai.ex`)

When `opts[:tools]` is present, route through ToolLoop instead of direct provider call.

**Change to `chat/2`:**

```elixir
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

**Provider chat/2 integration with tools_json:**

Each adapter's `chat/2` needs to check for `opts[:tools_json]` and include it in the request body:

```elixir
# In each adapter's chat/2 body construction:
body =
  %{"model" => model, "messages" => format_messages(messages)}
  |> maybe_put("tools", Keyword.get(opts, :tools_json))
  |> maybe_put("temperature", Keyword.get(opts, :temperature))
  # ...
```

### 6. Provider chat/2 Modifications

Each adapter's `chat/2` needs a small addition to pass `tools_json` into the request body:

- **OpenAI:** Add `|> maybe_put("tools", Keyword.get(opts, :tools_json))` to body construction
- **Anthropic:** Same — add `|> maybe_put("tools", Keyword.get(opts, :tools_json))` to body construction
- **OpenRouter:** Same

This is a one-line change per adapter. The `tools_json` key is set by ToolLoop after calling `format_tools/1`.

## Testing Strategy

### Test Fixtures

**`test/support/fixtures/openai/chat_tool_call_response.json`** — OpenAI response requesting a tool call
**`test/support/fixtures/openai/chat_after_tool_result.json`** — OpenAI final response after tool result
**`test/support/fixtures/anthropic/messages_tool_call_response.json`** — Anthropic response with tool_use
**`test/support/fixtures/anthropic/messages_after_tool_result.json`** — Anthropic final response after tool result

### Unit Tests

1. **PhoenixAI.Tool tests** (`test/phoenix_ai/tool_test.exs`)
   - `to_json_schema/1` converts atom keys to string keys recursively
   - `to_json_schema/1` handles nested properties
   - `to_json_schema/1` converts atom type values (`:string` → `"string"`)
   - `name/1`, `description/1` delegate to module callbacks
   - Define a test tool module in test support

2. **format_tools/1 tests** per adapter
   - OpenAI wraps in `type: "function"` envelope
   - Anthropic uses `input_schema` key
   - OpenRouter same as OpenAI

3. **Anthropic format_message tests** for new clauses
   - `:tool` role → `role: "user"` with `tool_result` content block
   - `:assistant` with tool_calls → content blocks with `tool_use` types
   - Mixed text + tool_use content blocks

4. **ToolLoop tests** (`test/phoenix_ai/tool_loop_test.exs`) — Mox-based
   - Single iteration: provider returns tool_call → tool executes → provider returns final
   - Multi iteration: two rounds of tool calls before final response
   - Max iterations reached
   - Tool error sent to provider as tool result
   - Tool exception caught and sent as error
   - Unknown tool name → error tool result
   - Provider error aborts loop

5. **AI.chat/2 integration tests** — with tools option
   - With tools: routes through ToolLoop
   - Without tools: unchanged behavior

## Error Handling

| Scenario | Behavior |
|----------|----------|
| `tool.execute/2` returns `{:error, reason}` | Error sent as tool result to provider. Loop continues. |
| `tool.execute/2` raises exception | Exception caught, message sent as tool result. Loop continues. |
| Tool name not found in tools list | Error tool result: "Unknown tool: {name}". Loop continues. |
| Provider returns `{:error, _}` | Loop aborts, error propagated to caller. |
| Max iterations exceeded | `{:error, :max_iterations_reached}` |
| Missing API key | `{:error, {:missing_api_key, provider}}` (existing, before ToolLoop) |

## Files Changed

| File | Action | Description |
|------|--------|-------------|
| `lib/phoenix_ai/tool.ex` | Create | Tool behaviour + to_json_schema helper |
| `lib/phoenix_ai/tool_loop.ex` | Create | Recursive tool execution loop |
| `lib/phoenix_ai/providers/openai.ex` | Modify | Add format_tools/1 + tools_json in body |
| `lib/phoenix_ai/providers/anthropic.ex` | Modify | Add format_tools/1 + tool result format_message clauses + tools_json in body |
| `lib/phoenix_ai/providers/openrouter.ex` | Modify | Add format_tools/1 + tools_json in body |
| `lib/ai.ex` | Modify | Route to ToolLoop when tools present |
| `test/phoenix_ai/tool_test.exs` | Create | Tool behaviour and schema conversion tests |
| `test/phoenix_ai/tool_loop_test.exs` | Create | ToolLoop integration tests with Mox |
| `test/phoenix_ai/providers/anthropic_test.exs` | Modify | Add format_tools and tool message tests |
| `test/phoenix_ai/providers/openai_test.exs` | Modify | Add format_tools tests |
| `test/phoenix_ai/providers/openrouter_test.exs` | Modify | Add format_tools tests |
| `test/support/tools/weather_tool.ex` | Create | Test tool module for fixture-based testing |
| `test/support/fixtures/openai/chat_tool_call_response.json` | Create | OpenAI tool call response fixture |
| `test/support/fixtures/openai/chat_after_tool_result.json` | Create | OpenAI final response fixture |
| `test/support/fixtures/anthropic/messages_tool_call_response.json` | Create | Anthropic tool call response fixture |
| `test/support/fixtures/anthropic/messages_after_tool_result.json` | Create | Anthropic final response fixture |

## Success Criteria (from ROADMAP.md)

1. A module implementing `PhoenixAI.Tool` callbacks can be passed to a provider and its schema is serialized to the correct provider format
2. When the OpenAI adapter receives a tool call response, it injects `role: "tool"` messages with matching `tool_call_id` — not shared pipeline code
3. When the Anthropic adapter receives a tool call response, it injects `role: "user"` messages with `type: "tool_result"` content blocks — not shared pipeline code
4. The automatic tool loop (call provider → detect tool calls → execute tools → re-call provider → until stop) completes and returns the final response
5. Tool modules contain no OTP — they are plain modules with zero GenServer/process involvement

---

*Design approved: 2026-03-29*
*Approach: A — Bottom-up*
