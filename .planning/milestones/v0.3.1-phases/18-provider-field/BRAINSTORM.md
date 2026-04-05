# Phase 18: Provider Field — Design Spec

**Date:** 2026-04-05
**Phase:** 18-provider-field
**Status:** Approved

## Goal

Add `:provider` field to `%PhoenixAI.Response{}` so downstream consumers can identify the originating provider without extra configuration.

## Approach

**Approach A: Set in each adapter's `parse_response/1`** (selected)

Each adapter hardcodes its provider atom in the `%Response{}` it constructs inside `parse_response/1`. This follows the v0.2.0 pattern where `Usage.from_provider/2` normalizes at the adapter boundary.

**Rejected alternatives:**
- **B: Central dispatch** — Would break the contract where `parse_response/1` returns a complete Response. Callers using `parse_response/1` directly would get `nil`.
- **C: Hybrid** — Overengineering for a simple additive field.

## Changes

### 1. Response Struct (`lib/phoenix_ai/response.ex`)

Add `provider: atom() | nil` to both `@type t` and `defstruct`. Default `nil` for backward compatibility. Position after `:model` for semantic affinity.

```elixir
@type t :: %__MODULE__{
        content: String.t() | nil,
        parsed: map() | nil,
        tool_calls: [PhoenixAI.ToolCall.t()],
        usage: Usage.t(),
        finish_reason: String.t() | nil,
        model: String.t() | nil,
        provider: atom() | nil,
        provider_response: map()
      }

defstruct [
  :content,
  :parsed,
  :finish_reason,
  :model,
  :provider,
  tool_calls: [],
  usage: %Usage{},
  provider_response: %{}
]
```

### 2. Provider Adapters

| Adapter | File | Line | Change |
|---------|------|------|--------|
| OpenAI | `lib/phoenix_ai/providers/openai.ex` | ~60 | Add `provider: :openai` to `%Response{}` |
| Anthropic | `lib/phoenix_ai/providers/anthropic.ex` | ~213 | Add `provider: :anthropic` to `%Response{}` |
| OpenRouter | `lib/phoenix_ai/providers/openrouter.ex` | ~36 | Add `provider: :openrouter` to `%Response{}` |
| TestProvider | `lib/phoenix_ai/providers/test_provider.ex` | 94 | Change from `def parse_response(body), do: body` to `def parse_response(body), do: %{body \| provider: :test}` |

### 3. Tests

Add `assert response.provider == :expected_atom` in each provider's test file. Preferably within an existing test that already asserts on the Response struct.

### 4. Version Bump

`mix.exs` — change `version` to `"0.3.1"`.

## Out of Scope

| Item | Reason |
|------|--------|
| StreamChunk `:provider` | StreamChunk has no `:model` either — different abstraction level |
| Usage `:provider` | Usage normalization uses `from_provider/2` — provider is a function arg, not a field |
| Telemetry metadata | Already present — `do_chat/2` line 64 sets `meta = %{provider: provider_atom}` |
| Provider behaviour change | `parse_response/1` signature unchanged |

## Key Discovery

Telemetry events `[:phoenix_ai, :chat, :start]` and `[:phoenix_ai, :chat, :stop]` already carry `:provider` in metadata (from `opts[:provider]` in `lib/ai.ex:64`). No telemetry changes needed.

## Impact

- **Backward compatible** — new optional field defaults to `nil`
- **No behaviour change** — `parse_response/1` signature unchanged
- **Pattern matches unaffected** — existing `%Response{content: c}` matches still work
- **Enables:** `phoenix_ai_store` cost tracking reads `response.provider` + `response.model` for pricing lookup
