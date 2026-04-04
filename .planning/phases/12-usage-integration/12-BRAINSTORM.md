# Phase 12: Usage Integration — Design Spec

**Date:** 2026-04-03
**Phase:** 12-usage-integration
**Status:** Approved

## Summary

Wire `PhoenixAI.Usage` struct into `Response`, `StreamChunk`, and all 3 provider adapters so that every response from the library carries normalized usage data. Normalization happens at the adapter level — the closest point to raw provider data.

## Architecture

### Normalization Strategy: At the Adapter

Each provider adapter calls `Usage.from_provider/2` in both `parse_response/1` and `parse_chunk/1`. This keeps normalization co-located with the provider-specific parsing logic.

```
Provider JSON → adapter.parse_response() → Usage.from_provider(:provider, raw) → %Response{usage: %Usage{}}
Provider SSE  → adapter.parse_chunk()    → Usage.from_provider(:provider, raw) → %StreamChunk{usage: %Usage{} | nil}
```

### Key Design Decision: Nil Preservation in Streaming

In `parse_chunk/1`, intermediary chunks have no usage data (`"usage"` key absent from JSON). These MUST remain `usage: nil` on the `StreamChunk` so the stream accumulator knows the final usage hasn't arrived yet. Only the final chunk carries actual usage data.

```elixir
# In each adapter's parse_chunk:
raw_usage = Map.get(json, "usage")
usage = if raw_usage, do: Usage.from_provider(:provider, raw_usage), else: nil
```

This differs from `parse_response/1` where `Usage.from_provider(:provider, nil)` returning `%Usage{}` zerado is fine — a completed response always has usage.

## Components

### Files to Modify

| File | Change | Lines |
|------|--------|-------|
| `lib/phoenix_ai/response.ex` | `usage: map()` → `usage: Usage.t()`, default `%Usage{}` | 8, 20 |
| `lib/phoenix_ai/stream_chunk.ex` | `usage: map() \| nil` → `usage: Usage.t() \| nil` | 8 |
| `lib/phoenix_ai/providers/openai.ex` | Call `Usage.from_provider(:openai, ...)` in `parse_response/1` and `parse_chunk/1` | 57, 145 |
| `lib/phoenix_ai/providers/anthropic.ex` | Call `Usage.from_provider(:anthropic, ...)` in `parse_response/1` and `parse_chunk/1` | 156, 198 |
| `lib/phoenix_ai/providers/openrouter.ex` | Call `Usage.from_provider(:openrouter, ...)` in `parse_response/1`. Replace `parse_chunk` delegation with own implementation using `:openrouter` atom | 34, 123 |
| `lib/phoenix_ai/stream.ex` | Explicit nil check for usage accumulation. `%Usage{}` default in `build_response/1` | 164, 187 |
| `lib/ai.ex` | Remove `\|\| %{}` from telemetry — pass `%Usage{}` struct directly | 112 |

### Test Files to Update

| File | Change | Lines |
|------|--------|-------|
| `test/phoenix_ai/providers/openai_test.exs` | `usage["prompt_tokens"]` → `usage.input_tokens` | 22-23 |
| `test/phoenix_ai/providers/anthropic_test.exs` | `usage["input_tokens"]` → `usage.input_tokens` | 22-23 |
| `test/phoenix_ai/providers/openrouter_test.exs` | `usage["prompt_tokens"]` → `usage.input_tokens` | 22-23 |
| `test/phoenix_ai/stream_test.exs` | `usage == %{...}` → match `%Usage{}` | 116, 233 |
| `test/phoenix_ai/stream_tools_test.exs` | `usage == %{...}` → match `%Usage{}` | 182 |
| `test/phoenix_ai/response_test.exs` | `usage == %{}` → `usage == %Usage{}` | 36 |
| `test/phoenix_ai/providers/provider_contract_test.exs` | `is_map(response.usage)` → `is_struct(response.usage, Usage)` (optional — `is_map` still works) | 43 |

## Detailed Changes

### 1. Response Struct (`response.ex`)

```elixir
# Add alias
alias PhoenixAI.Usage

# Type change
@type t :: %__MODULE__{
  ...
  usage: Usage.t(),
  ...
}

# Default change
defstruct [
  ...
  usage: %Usage{},
  ...
]
```

### 2. StreamChunk Struct (`stream_chunk.ex`)

```elixir
# Add alias
alias PhoenixAI.Usage

# Type change only (no default change — nil is correct for chunks)
@type t :: %__MODULE__{
  ...
  usage: Usage.t() | nil
}
```

### 3. OpenAI Adapter (`openai.ex`)

```elixir
# Add Usage to alias list
alias PhoenixAI.{Error, Message, Response, StreamChunk, ToolCall, Usage}

# parse_response/1 (line 57):
usage = body |> Map.get("usage") |> Usage.from_provider(:openai)

# parse_chunk/1 (line 145):
raw_usage = Map.get(json, "usage")
# ...
usage: if(raw_usage, do: Usage.from_provider(:openai, raw_usage), else: nil)
```

### 4. Anthropic Adapter (`anthropic.ex`)

```elixir
# Add Usage to alias list
alias PhoenixAI.{Error, Message, Response, StreamChunk, ToolCall, Usage}

# parse_response/1 (line 198):
usage = body |> Map.get("usage") |> Usage.from_provider(:anthropic)

# parse_chunk/1 for message_delta (line 156):
raw_usage = Map.get(json, "usage")
# ...
usage: if(raw_usage, do: Usage.from_provider(:anthropic, raw_usage), else: nil)
```

### 5. OpenRouter Adapter (`openrouter.ex`)

```elixir
# Add Usage and StreamChunk to alias list (StreamChunk wasn't needed before since it delegated)
alias PhoenixAI.{Error, Message, Response, StreamChunk, ToolCall, Usage}
# Remove: alias PhoenixAI.Providers.OpenAI (if only used for parse_chunk delegation)

# parse_response/1 (line 34):
usage = body |> Map.get("usage") |> Usage.from_provider(:openrouter)

# parse_chunk/1 — NEW implementation (replaces delegation to OpenAI):
@impl PhoenixAI.Provider
def parse_chunk(%{data: "[DONE]"}), do: %StreamChunk{finish_reason: "stop"}

def parse_chunk(%{data: data}) do
  json = Jason.decode!(data)
  choice = json |> Map.get("choices", []) |> List.first(%{})
  delta = Map.get(choice, "delta", %{})
  tool_call_delta = extract_tool_call_delta(Map.get(delta, "tool_calls"))
  raw_usage = Map.get(json, "usage")

  %StreamChunk{
    delta: Map.get(delta, "content"),
    tool_call_delta: tool_call_delta,
    finish_reason: Map.get(choice, "finish_reason"),
    usage: if(raw_usage, do: Usage.from_provider(:openrouter, raw_usage), else: nil)
  }
end
```

Note: OpenRouter does NOT have `extract_tool_call_delta/1` — it currently delegates to OpenAI. Two options: (a) copy the helper from OpenAI into OpenRouter, or (b) keep the `alias PhoenixAI.Providers.OpenAI` and call `OpenAI.parse_chunk/1` for tool_call_delta extraction only, then override usage. Option (a) is cleaner — copy the 2 private helper clauses (`extract_tool_call_delta/1`).

### 6. Stream Accumulator (`stream.ex`)

```elixir
# Add Usage to alias list
alias PhoenixAI.{Error, Response, StreamChunk, ToolCall, ToolLoop, Usage}

# Line 164 — explicit nil check (D-07):
new_usage = if chunk.usage != nil, do: chunk.usage, else: acc.usage

# Line 187 — build_response default (D-08):
usage: acc.usage || %Usage{}
```

### 7. Telemetry (`ai.ex`)

```elixir
# Line 112 — simplified (D-09):
defp telemetry_stop_meta({:ok, %PhoenixAI.Response{usage: usage}}) do
  %{status: :ok, usage: usage}
end
```

## Testing Strategy

All existing tests are updated inline (D-10). No new test files needed — the `usage_test.exs` from Phase 11 already covers the struct and factory.

**Provider test changes** — assertions switch from string-key map access to atom-key struct access:
```elixir
# Before:
assert response.usage["prompt_tokens"] == 10
assert response.usage["completion_tokens"] == 9

# After:
assert response.usage.input_tokens == 10
assert response.usage.output_tokens == 9
```

**Stream test changes** — assertions switch from raw map comparison to struct comparison:
```elixir
# Before:
assert result.usage == %{"prompt_tokens" => 10, "completion_tokens" => 5, "total_tokens" => 15}

# After:
assert %Usage{input_tokens: 10, output_tokens: 5, total_tokens: 15} = result.usage
```

## Design Decisions Summary

| ID | Decision | Rationale |
|----|----------|-----------|
| D-07 | Explicit nil check in stream accumulator | `%Usage{}` zerado is truthy — `\|\|` doesn't work as fallback |
| D-08 | `%Usage{}` default in `build_response` | Consistent with struct type on Response |
| D-09 | Pass struct directly to telemetry | No existing consumers to break, more type-safe |
| D-10 | Update test assertions inline | Simple, direct, no abstractions needed |
| D-11 | Normalize in adapters, not centrally | Co-locate normalization with provider-specific parsing |
| D-12 | Preserve nil in parse_chunk | Intermediary chunks must have `usage: nil` for accumulator logic |
| D-13 | OpenRouter gets own parse_chunk | Each adapter uses its own provider atom for consistency |

## Scope Boundary

This phase completes the v0.2.0 milestone. After this:
- `Response.usage` is always `%Usage{}`
- `StreamChunk.usage` is `%Usage{}` or `nil`
- No raw usage maps escape adapter boundaries
- All existing tests pass with updated assertions

---
*Design approved: 2026-04-03*
