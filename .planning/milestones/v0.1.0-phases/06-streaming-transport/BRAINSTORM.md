# Phase 6: Streaming Transport — Design Spec

**Date:** 2026-03-30
**Status:** Approved
**Context:** `.planning/phases/06-streaming-transport/06-CONTEXT.md`

## Overview

Central streaming module (`PhoenixAI.Stream`) handles Finch SSE connections, stateful buffer parsing via `server_sent_events`, and per-provider chunk conversion. The public API `AI.stream/2` resolves delivery mechanism (callback/PID/self) and delegates. Each adapter implements `parse_chunk/1` and `build_stream_body` — thin translation only.

**Requirements covered:** STREAM-01, STREAM-02, STREAM-03, STREAM-04

## Architecture: Central Streaming Module

Modeled after laravel/ai's `PrismGateway.streamText()` — one central module for all providers. Adapters are thin translators (parse_chunk only). SSE parsing delegated to `server_sent_events` library.

```
AI.stream/2 (lib/ai.ex)
  ├── resolve provider, merge config, validate api_key
  ├── build_callback(opts) — :on_chunk | :to | self()
  └── PhoenixAI.Stream.run/4 (lib/phoenix_ai/stream.ex)
        ├── provider_mod.build_stream_body() — body with stream: true
        ├── Finch.stream/5 via PhoenixAI.Finch pool
        ├── ServerSentEvents.parse() — stateful buffer, \n\n detection
        ├── provider_mod.parse_chunk/1 — %{event, data} → %StreamChunk{}
        ├── callback.(chunk) — deliver to caller
        ├── Accumulate content + usage
        └── {:ok, %Response{content: "full text", usage: %{...}}}
```

## Modules and Responsibilities

### `PhoenixAI.Stream` — Central Streaming Transport (NEW)

Owns the entire streaming lifecycle: build request, open Finch connection, parse SSE, dispatch chunks, accumulate response.

```elixir
defmodule PhoenixAI.Stream do
  @spec run(module(), [Message.t()], (StreamChunk.t() -> any()), keyword()) ::
          {:ok, Response.t()} | {:error, term()}
  def run(provider_mod, messages, callback, opts)
end
```

**Internal accumulator:**

```elixir
%{
  parser: ServerSentEvents.new(),    # SSE parser state
  provider_mod: provider_mod,         # adapter module
  callback: callback,                 # caller's chunk handler
  content: "",                        # accumulated text
  usage: %{},                         # filled from final chunk
  last_chunk: nil                     # detect finish_reason
}
```

**Finch integration via `Finch.stream/5`:**

```elixir
Finch.stream(request, PhoenixAI.Finch, acc, fn
  {:status, status}, acc -> handle_status(status, acc)
  {:headers, headers}, acc -> handle_headers(headers, acc)
  {:data, data}, acc -> handle_data(data, acc)
end)
```

**`handle_data` flow:**
1. Feed bytes into `ServerSentEvents.parse(acc.parser, data)`
2. For each complete SSE event → `provider_mod.parse_chunk(%{event: event, data: data})`
3. Invoke `callback.(chunk)` for non-nil chunks with delta
4. Accumulate `chunk.delta` into `acc.content`
5. Detect `finish_reason != nil` → stream complete

**Error handling:**
- HTTP status != 200 → `{:error, %Error{status: status, ...}}`
- Finch connection error → `{:error, %Error{message: reason, ...}}`
- JSON decode error in parse_chunk → chunk ignored (resilient, no crash)

### `AI.stream/2` — Public API (MODIFY lib/ai.ex)

Same pattern as `AI.chat/2` — resolve, config, validate, delegate.

```elixir
def stream(messages, opts \\ []) do
  provider_atom = opts[:provider] || default_provider()

  case resolve_provider(provider_atom) do
    {:ok, provider_mod} ->
      merged_opts = Config.resolve(provider_atom, Keyword.delete(opts, :provider))
      dispatch_stream(provider_mod, messages, merged_opts, provider_atom)
    {:error, _} = error ->
      error
  end
end

defp dispatch_stream(provider_mod, messages, opts, provider_atom) do
  case Keyword.get(opts, :api_key) do
    nil -> {:error, {:missing_api_key, provider_atom}}
    _key ->
      callback = build_callback(opts)
      PhoenixAI.Stream.run(provider_mod, messages, callback, opts)
  end
end

defp build_callback(opts) do
  cond do
    fun = Keyword.get(opts, :on_chunk) -> fun
    pid = Keyword.get(opts, :to)       -> &send(pid, {:phoenix_ai, {:chunk, &1}})
    true                               -> &send(self(), {:phoenix_ai, {:chunk, &1}})
  end
end
```

**Delivery priority:** `:on_chunk` callback > `:to` PID > `self()` default.

**Not supported in Phase 6:** Schema + streaming (blocked, same as laravel/ai).

### Provider Adapters — `parse_chunk/1` + `build_stream_body` (MODIFY)

**Interface:** `parse_chunk/1` receives `%{event: String.t() | nil, data: String.t()}` and returns `%StreamChunk{}` or `nil` (ignored event).

**Request building:** Each adapter also exposes `stream_url/1` and `stream_headers/1` (or reuses existing URL/headers logic). `PhoenixAI.Stream.run/4` calls these to construct the `Finch.build(:post, url, headers, body)` request. This keeps the central module provider-agnostic — it never hardcodes URLs or auth headers.

**OpenAI:**

```elixir
def parse_chunk(%{data: "[DONE]"}), do: %StreamChunk{finish_reason: "stop"}
def parse_chunk(%{data: data}) do
  json = Jason.decode!(data)
  delta = get_in(json, ["choices", Access.at(0), "delta"])
  %StreamChunk{
    delta: delta["content"],
    finish_reason: get_in(json, ["choices", Access.at(0), "finish_reason"])
  }
end

def build_stream_body(model, formatted_messages, opts) do
  build_body(model, formatted_messages, opts)
  |> Map.put("stream", true)
  |> Map.put("stream_options", %{"include_usage" => true})
end
```

**Anthropic:**

```elixir
def parse_chunk(%{event: "content_block_delta", data: data}) do
  json = Jason.decode!(data)
  %StreamChunk{delta: json["delta"]["text"]}
end
def parse_chunk(%{event: "message_delta", data: data}) do
  json = Jason.decode!(data)
  %StreamChunk{finish_reason: json["delta"]["stop_reason"]}
end
def parse_chunk(%{event: "message_stop", data: _}), do: %StreamChunk{finish_reason: "stop"}
def parse_chunk(_), do: nil  # ping, message_start, content_block_start, etc.

def build_stream_body(model, formatted_messages, opts) do
  build_body(model, formatted_messages, opts)
  |> Map.put("stream", true)
end
```

**OpenRouter:** Delegates to OpenAI (API-compatible).

```elixir
def parse_chunk(event_data), do: PhoenixAI.Providers.OpenAI.parse_chunk(event_data)

def build_stream_body(model, formatted_messages, opts) do
  build_body(model, formatted_messages, opts)
  |> Map.put("stream", true)
  |> Map.put("stream_options", %{"include_usage" => true})
end
```

### `mix.exs` — Add dependency (MODIFY)

```elixir
{:server_sent_events, "~> 0.2"}
```

### Provider Behaviour — No change needed

`stream/3` and `parse_chunk/1` already defined as `@optional_callbacks`.

Note: The existing `Provider.stream/3` callback signature takes a positional `callback` argument. `AI.stream/2` builds the callback from opts and passes it to `Stream.run/4`, which then calls `provider_mod.parse_chunk/1` (not `stream/3`). The `stream/3` callback on the behaviour remains available for consumers who want to call a provider directly, but Phase 6's central module uses `parse_chunk/1` + `build_stream_body` instead.

### `%StreamChunk{}` — No change needed

Already has `delta`, `tool_call_delta`, `finish_reason`. `tool_call_delta` usage deferred to Phase 7.

### `PhoenixAI.child_spec/1` — No change needed

Finch pool already supervised under `PhoenixAI.Finch`.

## Task-per-Session (STREAM-04)

`PhoenixAI.Stream.run/4` is a synchronous function — blocking until stream completes. The caller decides concurrency:

- Direct call → blocks the caller (fine for scripts/IEx)
- Inside `Task.async` → one Task per stream session
- Inside GenServer `handle_info` → non-blocking with message delivery via `:to`

This guarantees one Task per session without the Stream module forcing it. Maximum flexibility for the consumer.

## Testing Strategy

### Layer 1: parse_chunk/1 unit tests (inline strings)

Per-adapter tests. Fast, readable, no fixtures needed.

- OpenAI: delta extraction, [DONE] sentinel, finish_reason, nil content
- Anthropic: content_block_delta, message_delta, message_stop, ignored events (ping, message_start)
- OpenRouter: delegates to OpenAI (verify delegation)

### Layer 2: SSE parser fragmentation tests (binary fixtures)

```
test/fixtures/sse/
  openai_simple.sse
  openai_fragmented.sse
  anthropic_simple.sse
  anthropic_fragmented.sse
```

Test that `ServerSentEvents.parse/2` correctly reassembles events split across TCP packet boundaries.

### Layer 3: Stream.run/4 integration tests (Mox)

Mock at the Finch level to simulate streaming responses. Verify:
- Callback invoked with correct chunks in order
- Response.content contains accumulated text
- Response.usage populated from final chunk
- Error cases: non-200 status, connection failure

### Not tested (out of scope):
- Finch HTTP internals (tested by Finch)
- SSE parser internals (tested by server_sent_events)
- Real network calls (Bypass — deferred, overkill for v1)

## Files Changed Summary

| File | Action | What |
|------|--------|------|
| `mix.exs` | Modify | Add `server_sent_events ~> 0.2` |
| `lib/phoenix_ai/stream.ex` | Create | Central streaming module |
| `lib/ai.ex` | Modify | Add `stream/2`, `build_callback/1`, `dispatch_stream/4` |
| `lib/phoenix_ai/providers/openai.ex` | Modify | Add `parse_chunk/1`, `build_stream_body/3` |
| `lib/phoenix_ai/providers/anthropic.ex` | Modify | Add `parse_chunk/1`, `build_stream_body/4` |
| `lib/phoenix_ai/providers/openrouter.ex` | Modify | Add `parse_chunk/1`, `build_stream_body/3` |
| `test/phoenix_ai/providers/openai_stream_test.exs` | Create | parse_chunk unit tests |
| `test/phoenix_ai/providers/anthropic_stream_test.exs` | Create | parse_chunk unit tests |
| `test/phoenix_ai/providers/openrouter_stream_test.exs` | Create | parse_chunk unit tests |
| `test/phoenix_ai/stream_test.exs` | Create | Stream.run integration + fragmentation tests |
| `test/phoenix_ai/ai_stream_test.exs` | Create | AI.stream/2 public API tests |
| `test/fixtures/sse/*.sse` | Create | Binary SSE fixtures |

## Out of Scope (Phase 7+)

- `tool_call_delta` handling in StreamChunk
- Streaming + tool calling combined
- Schema + streaming (blocked)
- `Agent.stream/2` (agent-level streaming)

---

*Phase: 06-streaming-transport*
*Design approved: 2026-03-30*
