# Usage Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire `PhoenixAI.Usage` struct into `Response`, `StreamChunk`, and all 3 provider adapters so no raw usage maps escape adapter boundaries.

**Architecture:** Each provider adapter calls `Usage.from_provider/2` at the point where raw usage is extracted from the provider JSON. Response and StreamChunk type annotations change from `map()` to `Usage.t()`. Stream accumulator uses explicit nil checks instead of `||` truthiness.

**Tech Stack:** Elixir, ExUnit

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `lib/phoenix_ai/response.ex` | Modify | Change `usage` type from `map()` to `Usage.t()`, default `%Usage{}` |
| `lib/phoenix_ai/stream_chunk.ex` | Modify | Change `usage` type from `map() \| nil` to `Usage.t() \| nil` |
| `lib/phoenix_ai/providers/openai.ex` | Modify | Call `Usage.from_provider(:openai, ...)` in parse_response and parse_chunk |
| `lib/phoenix_ai/providers/anthropic.ex` | Modify | Call `Usage.from_provider(:anthropic, ...)` in parse_response and parse_chunk |
| `lib/phoenix_ai/providers/openrouter.ex` | Modify | Call `Usage.from_provider(:openrouter, ...)` in parse_response. Replace parse_chunk delegation with own implementation |
| `lib/phoenix_ai/stream.ex` | Modify | Explicit nil check in accumulator, `%Usage{}` default in build_response |
| `lib/ai.ex` | Modify | Simplify telemetry metadata — remove `\|\| %{}` fallback |
| `test/phoenix_ai/response_test.exs` | Modify | Update default usage assertion |
| `test/phoenix_ai/providers/openai_test.exs` | Modify | Update usage assertions to struct access |
| `test/phoenix_ai/providers/anthropic_test.exs` | Modify | Update usage assertions to struct access |
| `test/phoenix_ai/providers/openrouter_test.exs` | Modify | Update usage assertions to struct access |
| `test/phoenix_ai/providers/provider_contract_test.exs` | Modify | Update `is_map` to `is_struct` assertion |
| `test/phoenix_ai/stream_test.exs` | Modify | Update usage assertions to struct matching |
| `test/phoenix_ai/stream_tools_test.exs` | Modify | Update usage assertions to struct matching |

---

### Task 1: Response/StreamChunk Struct Types + OpenAI Adapter

**Files:**
- Modify: `lib/phoenix_ai/response.ex`
- Modify: `lib/phoenix_ai/stream_chunk.ex`
- Modify: `lib/phoenix_ai/providers/openai.ex`
- Modify: `test/phoenix_ai/response_test.exs`
- Modify: `test/phoenix_ai/providers/openai_test.exs`
- Modify: `test/phoenix_ai/providers/provider_contract_test.exs`

- [ ] **Step 1: Update Response struct type and default**

In `lib/phoenix_ai/response.ex`, add alias and change usage type:

```elixir
defmodule PhoenixAI.Response do
  @moduledoc "Represents a completed response from an AI provider."

  alias PhoenixAI.Usage

  @type t :: %__MODULE__{
          content: String.t() | nil,
          parsed: map() | nil,
          tool_calls: [PhoenixAI.ToolCall.t()],
          usage: Usage.t(),
          finish_reason: String.t() | nil,
          model: String.t() | nil,
          provider_response: map()
        }

  defstruct [
    :content,
    :parsed,
    :finish_reason,
    :model,
    tool_calls: [],
    usage: %Usage{},
    provider_response: %{}
  ]
end
```

- [ ] **Step 2: Update StreamChunk type**

In `lib/phoenix_ai/stream_chunk.ex`, add alias and change usage type:

```elixir
defmodule PhoenixAI.StreamChunk do
  @moduledoc "Stub for a single chunk emitted during a streaming AI response. (Phase 6)"

  alias PhoenixAI.Usage

  @type t :: %__MODULE__{
          delta: String.t() | nil,
          tool_call_delta: map() | nil,
          finish_reason: String.t() | nil,
          usage: Usage.t() | nil
        }

  defstruct [:delta, :tool_call_delta, :finish_reason, :usage]
end
```

- [ ] **Step 3: Update OpenAI adapter to normalize usage**

In `lib/phoenix_ai/providers/openai.ex`:

Add `Usage` to the alias line:
```elixir
alias PhoenixAI.{Error, Message, Response, StreamChunk, ToolCall, Usage}
```

Change `parse_response/1` (around line 57):
```elixir
  # Before:
  # usage = Map.get(body, "usage", %{})
  # After:
  usage = body |> Map.get("usage") |> Usage.from_provider(:openai)
```

Change `parse_chunk/1` (around line 145):
```elixir
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
      usage: if(raw_usage, do: Usage.from_provider(:openai, raw_usage), else: nil)
    }
  end
```

- [ ] **Step 4: Update response_test.exs**

In `test/phoenix_ai/response_test.exs`:

Add alias at top:
```elixir
  alias PhoenixAI.Usage
```

Change line 36 — "usage defaults to empty map":
```elixir
    test "usage defaults to empty Usage struct" do
      resp = %Response{content: "hi"}
      assert resp.usage == %Usage{}
    end
```

Change line 50 — "usage can be set with token counts":
```elixir
    test "usage can be set with token counts" do
      resp = %Response{content: "hi", usage: %Usage{input_tokens: 10, output_tokens: 5}}
      assert resp.usage.input_tokens == 10
      assert resp.usage.output_tokens == 5
    end
```

- [ ] **Step 5: Update openai_test.exs**

In `test/phoenix_ai/providers/openai_test.exs`, change lines 22-23:
```elixir
      # Before:
      # assert response.usage["prompt_tokens"] == 10
      # assert response.usage["completion_tokens"] == 9
      # After:
      assert response.usage.input_tokens == 10
      assert response.usage.output_tokens == 9
```

- [ ] **Step 6: Update provider_contract_test.exs**

In `test/phoenix_ai/providers/provider_contract_test.exs`, change line 43:
```elixir
      # Before:
      # assert is_map(response.usage)
      # After:
      assert %PhoenixAI.Usage{} = response.usage
```

- [ ] **Step 7: Run tests to verify**

Run: `mix test test/phoenix_ai/response_test.exs test/phoenix_ai/providers/openai_test.exs test/phoenix_ai/providers/provider_contract_test.exs`
Expected: All pass

- [ ] **Step 8: Commit**

```bash
git add lib/phoenix_ai/response.ex lib/phoenix_ai/stream_chunk.ex lib/phoenix_ai/providers/openai.ex test/phoenix_ai/response_test.exs test/phoenix_ai/providers/openai_test.exs test/phoenix_ai/providers/provider_contract_test.exs
git commit -m "feat(usage): integrate Usage struct into Response, StreamChunk, and OpenAI adapter"
```

---

### Task 2: Anthropic Adapter

**Files:**
- Modify: `lib/phoenix_ai/providers/anthropic.ex`
- Modify: `test/phoenix_ai/providers/anthropic_test.exs`

- [ ] **Step 1: Update Anthropic adapter to normalize usage**

In `lib/phoenix_ai/providers/anthropic.ex`:

Add `Usage` to the alias line:
```elixir
alias PhoenixAI.{Error, Message, Response, StreamChunk, ToolCall, Usage}
```

Change `parse_response/1` (around line 198):
```elixir
  # Before:
  # usage = Map.get(body, "usage", %{})
  # After:
  usage = body |> Map.get("usage") |> Usage.from_provider(:anthropic)
```

Change `parse_chunk/1` for `message_delta` event (around line 151-158):
```elixir
  def parse_chunk(%{event: "message_delta", data: data}) do
    json = Jason.decode!(data)
    raw_usage = Map.get(json, "usage")

    %StreamChunk{
      finish_reason: get_in(json, ["delta", "stop_reason"]),
      usage: if(raw_usage, do: Usage.from_provider(:anthropic, raw_usage), else: nil)
    }
  end
```

- [ ] **Step 2: Update anthropic_test.exs**

In `test/phoenix_ai/providers/anthropic_test.exs`, change lines 22-23:
```elixir
      # Before:
      # assert response.usage["input_tokens"] == 10
      # assert response.usage["output_tokens"] == 9
      # After:
      assert response.usage.input_tokens == 10
      assert response.usage.output_tokens == 9
```

- [ ] **Step 3: Run tests to verify**

Run: `mix test test/phoenix_ai/providers/anthropic_test.exs`
Expected: All pass

- [ ] **Step 4: Commit**

```bash
git add lib/phoenix_ai/providers/anthropic.ex test/phoenix_ai/providers/anthropic_test.exs
git commit -m "feat(usage): integrate Usage struct into Anthropic adapter"
```

---

### Task 3: OpenRouter Adapter (Own parse_chunk)

**Files:**
- Modify: `lib/phoenix_ai/providers/openrouter.ex`
- Modify: `test/phoenix_ai/providers/openrouter_test.exs`

- [ ] **Step 1: Update OpenRouter adapter**

In `lib/phoenix_ai/providers/openrouter.ex`:

Change the alias lines. Add `StreamChunk`, `ToolCall`, `Usage`. Remove the `OpenAI` alias if it was only used for `parse_chunk` delegation (check first — it may be used elsewhere):

```elixir
alias PhoenixAI.{Error, Message, Response, StreamChunk, ToolCall, Usage}
```

Check if `alias PhoenixAI.Providers.OpenAI` is used anywhere else in the file besides `parse_chunk`. If not, remove it.

Change `parse_response/1` (around line 34):
```elixir
  # Before:
  # usage = Map.get(body, "usage", %{})
  # After:
  usage = body |> Map.get("usage") |> Usage.from_provider(:openrouter)
```

Replace the `parse_chunk` delegation (line 123) with own implementation:
```elixir
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

- [ ] **Step 2: Update openrouter_test.exs**

In `test/phoenix_ai/providers/openrouter_test.exs`, change lines 22-23:
```elixir
      # Before:
      # assert response.usage["prompt_tokens"] == 10
      # assert response.usage["completion_tokens"] == 9
      # After:
      assert response.usage.input_tokens == 10
      assert response.usage.output_tokens == 9
```

- [ ] **Step 3: Run tests to verify**

Run: `mix test test/phoenix_ai/providers/openrouter_test.exs`
Expected: All pass

- [ ] **Step 4: Commit**

```bash
git add lib/phoenix_ai/providers/openrouter.ex test/phoenix_ai/providers/openrouter_test.exs
git commit -m "feat(usage): integrate Usage struct into OpenRouter adapter with own parse_chunk"
```

---

### Task 4: Stream.ex + Telemetry + Remaining Test Fixes

**Files:**
- Modify: `lib/phoenix_ai/stream.ex`
- Modify: `lib/ai.ex`
- Modify: `test/phoenix_ai/stream_test.exs`
- Modify: `test/phoenix_ai/stream_tools_test.exs`

- [ ] **Step 1: Update stream.ex accumulator logic**

In `lib/phoenix_ai/stream.ex`:

Add `Usage` to the alias line:
```elixir
alias PhoenixAI.{Error, Response, StreamChunk, ToolCall, ToolLoop, Usage}
```

Change line 164 in `apply_chunk/2` — explicit nil check (D-07):
```elixir
    # Before:
    # new_usage = chunk.usage || acc.usage
    # After:
    new_usage = if chunk.usage != nil, do: chunk.usage, else: acc.usage
```

Change line 187 in `build_response/1` — Usage struct default (D-08):
```elixir
    # Before:
    # usage: acc.usage || %{},
    # After:
    usage: acc.usage || %Usage{},
```

- [ ] **Step 2: Update telemetry in ai.ex**

In `lib/ai.ex`, change line 112 — remove `|| %{}` fallback (D-09):
```elixir
  # Before:
  # defp telemetry_stop_meta({:ok, %PhoenixAI.Response{usage: usage}}) do
  #   %{status: :ok, usage: usage || %{}}
  # end
  # After:
  defp telemetry_stop_meta({:ok, %PhoenixAI.Response{usage: usage}}) do
    %{status: :ok, usage: usage}
  end
```

- [ ] **Step 3: Update stream_test.exs**

In `test/phoenix_ai/stream_test.exs`:

Add alias at the top of the module:
```elixir
  alias PhoenixAI.Usage
```

Change lines 116-120 — "captures usage from chunk with usage field":
```elixir
      # Before:
      # assert result.usage == %{
      #          "prompt_tokens" => 10,
      #          "completion_tokens" => 5,
      #          "total_tokens" => 15
      #        }
      # After:
      assert %Usage{input_tokens: 10, output_tokens: 5, total_tokens: 15} = result.usage
```

Change line 233 — Anthropic stream usage:
```elixir
      # Before:
      # assert result.usage == %{"output_tokens" => 2}
      # After:
      assert %Usage{output_tokens: 2} = result.usage
```

- [ ] **Step 4: Update stream_tools_test.exs**

In `test/phoenix_ai/stream_tools_test.exs`:

Add alias at the top of the module:
```elixir
  alias PhoenixAI.Usage
```

Change lines 182-186:
```elixir
      # Before:
      # assert response.usage == %{
      #          "prompt_tokens" => 25,
      #          "completion_tokens" => 18,
      #          "total_tokens" => 43
      #        }
      # After:
      assert %Usage{input_tokens: 25, output_tokens: 18, total_tokens: 43} = response.usage
```

- [ ] **Step 5: Run full test suite**

Run: `mix test`
Expected: All 326 tests pass, 0 failures

- [ ] **Step 6: Run code quality checks**

Run: `mix format --check-formatted && mix credo --strict`
Expected: No issues

- [ ] **Step 7: Commit**

```bash
git add lib/phoenix_ai/stream.ex lib/ai.ex test/phoenix_ai/stream_test.exs test/phoenix_ai/stream_tools_test.exs
git commit -m "feat(usage): update stream accumulator, telemetry, and remaining tests"
```

---

## Verification Checklist

After all tasks complete, verify:

- [ ] `Response.usage` is typed as `Usage.t()` and defaults to `%Usage{}`
- [ ] `StreamChunk.usage` is typed as `Usage.t() | nil`
- [ ] OpenAI adapter calls `Usage.from_provider(:openai, ...)` in parse_response and parse_chunk
- [ ] Anthropic adapter calls `Usage.from_provider(:anthropic, ...)` in parse_response and parse_chunk
- [ ] OpenRouter adapter calls `Usage.from_provider(:openrouter, ...)` in parse_response and has own parse_chunk
- [ ] Stream accumulator uses explicit nil check (not `||`) for usage
- [ ] `build_response` defaults to `%Usage{}` not `%{}`
- [ ] Telemetry passes `%Usage{}` directly (no `|| %{}`)
- [ ] All existing tests updated and passing
- [ ] `mix format` and `mix credo --strict` clean
- [ ] No raw usage maps escape adapter boundaries
