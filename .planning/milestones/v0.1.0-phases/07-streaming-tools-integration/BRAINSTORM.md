# Phase 7: Streaming + Tools Integration — Design Spec

**Date:** 2026-03-30
**Status:** Approved
**Context:** `.planning/phases/07-streaming-tools-integration/07-CONTEXT.md`

## Goal

Streaming and tool calling work correctly together for OpenAI, Anthropic, and OpenRouter. During a streaming response, tool call deltas are accumulated into complete `%ToolCall{}` structs, tools are executed, results are injected, and the provider is re-called via streaming. All chunks (text and tool call deltas) are delivered to callers via callback or PID.

## Scope

**In scope:**
- Extend `parse_chunk/1` on each provider to handle tool call delta events
- Accumulate tool call fragments in `Stream.run/4` accumulator
- New `Stream.run_with_tools/5` wrapper for the streaming tool loop
- Extend `AI.stream/2` to accept `tools:` option
- Inject tools into `build_stream_body` for streaming requests
- SSE fixture files for both OpenAI and Anthropic tool call streaming
- Integration tests for the full round-trip

**Out of scope:**
- Schema + tools + streaming combined (schema validation deferred)
- Changes to the synchronous `ToolLoop.run/4`
- New tool behaviour callbacks

## Architecture

### Approach: `Stream.run_with_tools/5` wrapper over `Stream.run/4`

The streaming tool loop is a recursive wrapper around the existing `Stream.run/4`:

```
AI.stream/2
  └─ dispatch_stream (detects tools: option)
       └─ Stream.run_with_tools/5 (recursive tool loop)
            └─ Stream.run/4 (SSE transport + accumulation)
                 └─ Provider.parse_chunk/1 (per-provider delta parsing)
```

This keeps `Stream.run/4` focused on SSE transport while `run_with_tools/5` handles the tool calling orchestration layer.

## Detailed Design

### 1. Tool Call Delta Parsing (per provider)

Each adapter's `parse_chunk/1` gets new clauses for tool call events.

**OpenAI / OpenRouter:**

Tool calls arrive in `delta.tool_calls` within the standard choice structure:

```json
{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_abc","function":{"name":"get_weather","arguments":"{\"ci"}}]}}]}
```

- When `delta.tool_calls` exists, return `%StreamChunk{tool_call_delta: %{index: 0, id: "call_abc", name: "get_weather", arguments: "{\"ci"}}`.
- `id` and `name` only appear in the first chunk for each tool call index. Subsequent chunks only carry `arguments` fragments.
- OpenRouter delegates to `OpenAI.parse_chunk/1` — no changes needed.

**Anthropic:**

Tool calls arrive as typed events:

- `content_block_start` with `type: "tool_use"` → `%StreamChunk{tool_call_delta: %{index: content_index, id: id, name: name, arguments: ""}}`
- `content_block_delta` with `type: "input_json_delta"` → `%StreamChunk{tool_call_delta: %{index: content_index, arguments: partial_json}}`

The `content_index` from Anthropic's content block structure maps to the tool call index.

### 2. Tool Call Accumulation in Stream Accumulator

The accumulator map in `Stream.run/4` gains a new field:

```elixir
acc = %{
  remainder: "",
  provider_mod: provider_mod,
  callback: callback,
  content: "",
  usage: nil,
  finished: false,
  status: nil,
  tool_calls_acc: %{}  # %{index => %{id: _, name: _, arguments: ""}}
}
```

`apply_chunk/2` is extended with a new clause for tool call deltas:

```elixir
defp apply_chunk(%StreamChunk{tool_call_delta: delta} = chunk, acc) when delta != nil do
  # Deliver to callback (full transparency — D-07)
  acc.callback.(chunk)
  
  # Accumulate by index
  index = delta.index
  existing = Map.get(acc.tool_calls_acc, index, %{id: nil, name: nil, arguments: ""})
  
  updated = %{
    id: delta.id || existing.id,
    name: delta.name || existing.name,
    arguments: existing.arguments <> (delta.arguments || "")
  }
  
  %{acc | tool_calls_acc: Map.put(acc.tool_calls_acc, index, updated)}
end
```

`build_response/1` converts accumulated fragments to `[%ToolCall{}]`:

```elixir
def build_response(acc) do
  tool_calls =
    acc.tool_calls_acc
    |> Enum.sort_by(fn {index, _} -> index end)
    |> Enum.map(fn {_, tc} ->
      args = if tc.arguments != "", do: Jason.decode!(tc.arguments), else: %{}
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

### 3. Stream Tool Loop (`Stream.run_with_tools/5`)

A recursive wrapper over `Stream.run/4`:

```elixir
@spec run_with_tools(module(), [Message.t()], callback(), [module()], keyword()) ::
        {:ok, Response.t()} | {:error, term()}
def run_with_tools(provider_mod, messages, callback, tools, opts) do
  max_iterations = Keyword.get(opts, :max_iterations, 10)
  formatted_tools = provider_mod.format_tools(tools)
  stream_opts = Keyword.put(opts, :tools_json, formatted_tools)
  
  do_stream_loop(provider_mod, messages, callback, tools, stream_opts, max_iterations, 0)
end

defp do_stream_loop(_, _, _, _, _, max, iter) when iter >= max do
  {:error, :max_iterations_reached}
end

defp do_stream_loop(provider_mod, messages, callback, tools, opts, max, iter) do
  case run(provider_mod, messages, callback, opts) do
    {:ok, %Response{tool_calls: []} = response} ->
      {:ok, response}
      
    {:ok, %Response{tool_calls: tool_calls} = response} when tool_calls != [] ->
      assistant_msg = build_assistant_message(response)
      tool_result_msgs = execute_and_build_results(tool_calls, tools, opts)
      new_messages = messages ++ [assistant_msg | tool_result_msgs]
      do_stream_loop(provider_mod, new_messages, callback, tools, opts, max, iter + 1)
      
    {:error, _} = error ->
      error
  end
end
```

**Key behaviors:**
- Same recursion pattern as `ToolLoop.do_loop/6` — proven and understood
- Reuses tool execution helpers from `ToolLoop` (made public or extracted to shared helper)
- Every iteration is a full streaming round-trip — the callback receives chunks from each iteration
- `max_iterations` defaults to 10, same as synchronous ToolLoop

### 4. Public API Integration

**`AI.stream/2`** — `dispatch_stream/4` detects `tools:` in opts:

```elixir
defp dispatch_stream(provider_mod, messages, opts, provider_atom) do
  case Keyword.get(opts, :api_key) do
    nil ->
      {:error, {:missing_api_key, provider_atom}}
    _key ->
      callback = build_callback(opts)
      tools = Keyword.get(opts, :tools)
      stream_opts = Keyword.drop(opts, [:on_chunk, :to, :schema])
      
      if tools && tools != [] do
        PhoenixAI.Stream.run_with_tools(provider_mod, messages, callback, tools, stream_opts)
      else
        PhoenixAI.Stream.run(provider_mod, messages, callback, stream_opts)
      end
  end
end
```

**`build_stream_body`** — Each provider injects `tools_json` when present:

```elixir
# In build_stream_body, after building the base body:
case Keyword.get(opts, :tools_json) do
  nil -> body
  tools -> Map.put(body, "tools", tools)
end
```

### 5. Helper Extraction

`ToolLoop` helper functions need to be accessible from `Stream`:

**Option:** Make these functions public in ToolLoop:
- `ToolLoop.build_assistant_message/1` — builds `%Message{role: :assistant}` from response
- `ToolLoop.execute_and_build_results/3` — executes tools, builds result messages

This keeps tool execution logic in one place (ToolLoop) while Stream reuses it.

### 6. Testing Strategy

**Fixture files** (in `test/fixtures/sse/`):
- `openai_tool_call.sse` — Complete OpenAI streaming sequence with tool call chunks (name → argument fragments → finish)
- `anthropic_tool_call.sse` — Complete Anthropic streaming sequence with content_block_start (tool_use) → content_block_delta (input_json_delta) → message_delta

**Unit tests:**
- `parse_chunk/1` with tool call delta events (per provider)
- `apply_chunk/2` tool call accumulation logic
- `build_response/1` with accumulated tool calls

**Integration tests:**
- Full stream → accumulate tool calls → Response has correct ToolCalls
- Stream + tools round-trip: stream → detect tools → execute → re-stream → final response
- Multiple parallel tool calls (index 0, 1) in a single stream
- Tool execution error during streaming (error sent back, loop continues)
- `max_iterations_reached` for infinite tool loops

**Edge cases:**
- Tool call with empty arguments `{}`
- Tool call where arguments arrive as a single chunk (no fragmentation)
- Mixed content + tool call chunks in the same stream
- Anthropic content blocks with text followed by tool_use in the same response

### 7. Error Handling

- **Tool execution errors:** Sent back to provider as tool results, loop does not abort (per Phase 3 D-16/D-17)
- **Provider errors during re-stream:** `{:error, reason}` propagated immediately
- **Max iterations:** Returns `{:error, :max_iterations_reached}`
- **JSON decode error in arguments:** Fallback to `%{}` for malformed argument JSON
- **Connection errors:** Handled by existing `Stream.run/4` error paths (non-200 status, Finch exceptions)

## Files Affected

### Modified
- `lib/phoenix_ai/stream.ex` — Add `tool_calls_acc` to accumulator, extend `apply_chunk/2`, add `run_with_tools/5`
- `lib/phoenix_ai/stream_chunk.ex` — Update moduledoc only (tool_call_delta already exists)
- `lib/phoenix_ai/providers/openai.ex` — Extend `parse_chunk/1` for tool call deltas, extend `build_stream_body/3` for tools injection
- `lib/phoenix_ai/providers/anthropic.ex` — Extend `parse_chunk/1` for tool_use events, extend `build_stream_body/4` for tools injection
- `lib/phoenix_ai/tool_loop.ex` — Make `build_assistant_message/1` and `execute_and_build_results/3` public
- `lib/ai.ex` — Extend `dispatch_stream/4` to detect tools and route to `run_with_tools/5`

### Created
- `test/fixtures/sse/openai_tool_call.sse` — OpenAI streaming + tool call fixture
- `test/fixtures/sse/anthropic_tool_call.sse` — Anthropic streaming + tool call fixture
- `test/phoenix_ai/stream_tools_test.exs` — Integration tests for streaming + tools
- `test/phoenix_ai/providers/openai_stream_tools_test.exs` — OpenAI parse_chunk tool call tests
- `test/phoenix_ai/providers/anthropic_stream_tools_test.exs` — Anthropic parse_chunk tool call tests

### Unchanged
- `lib/phoenix_ai/providers/openrouter.ex` — Delegates to OpenAI, no changes needed
- `lib/phoenix_ai/tool_call.ex` — ToolCall struct unchanged
- `lib/phoenix_ai/response.ex` — Response struct already has `tool_calls` field

## Success Criteria (from ROADMAP.md)

1. A streaming response that includes mid-stream tool call events is parsed correctly — tool arguments arrive complete, not truncated
2. `AI.stream/2` with `on_chunk: fn chunk -> ... end` delivers `%StreamChunk{}` structs to the callback in arrival order (including tool call delta chunks)
3. `AI.stream/2` with `to: caller_pid` sends `{:phoenix_ai, {:chunk, %StreamChunk{}}}` messages to the target process
4. Streaming + tool calling round-trip passes fixture tests for both OpenAI and Anthropic — not just one provider

---

*Phase: 07-streaming-tools-integration*
*Design approved: 2026-03-30*
