# Phase 11: Usage Struct — Design Spec

**Date:** 2026-04-03
**Phase:** 11-usage-struct
**Status:** Approved

## Summary

Create `PhoenixAI.Usage`, a normalized struct that maps raw provider usage data into a consistent shape. Eliminates per-consumer normalization by centralizing the mapping logic in a single module with multi-clause `from_provider/2`.

## Architecture

### Module: `PhoenixAI.Usage`

**File:** `lib/phoenix_ai/usage.ex`

Single module containing the struct definition and factory function. No external dependencies beyond the standard library.

### Struct Definition

```elixir
@type t :: %__MODULE__{
  input_tokens: non_neg_integer(),
  output_tokens: non_neg_integer(),
  total_tokens: non_neg_integer(),
  cache_read_tokens: non_neg_integer() | nil,
  cache_creation_tokens: non_neg_integer() | nil,
  provider_specific: map()
}

defstruct [
  input_tokens: 0,
  output_tokens: 0,
  total_tokens: 0,
  cache_read_tokens: nil,
  cache_creation_tokens: nil,
  provider_specific: %{}
]
```

**Field semantics:**
- `input_tokens`, `output_tokens`, `total_tokens` — always `non_neg_integer()`, default `0`
- `cache_read_tokens`, `cache_creation_tokens` — `nil` when provider does not support caching (e.g., OpenAI), `non_neg_integer()` when supported (e.g., Anthropic). Distinguishes "not applicable" from "zero cached tokens".
- `provider_specific` — always a map (never nil), holds the original raw usage map exactly as received from the provider

### Factory: `from_provider/2`

**Spec:** `@spec from_provider(atom(), map() | nil) :: t()`

Public API (`@doc`). Never raises, never returns error tuples — pure transformation.

**Clause order:**

1. `from_provider(:openai, raw)` — maps `prompt_tokens` → `input_tokens`, `completion_tokens` → `output_tokens`, uses provider's `total_tokens`
2. `from_provider(:anthropic, raw)` — maps `input_tokens` directly, auto-calculates `total_tokens` as `input + output`, maps `cache_read_input_tokens` → `cache_read_tokens`, `cache_creation_input_tokens` → `cache_creation_tokens`
3. `from_provider(:openrouter, raw)` — delegates to `:openai` (same wire format)
4. `from_provider(_provider, nil)` — returns zero-valued `%Usage{}`
5. `from_provider(_provider, %{})` — returns zero-valued `%Usage{}`
6. `from_provider(_provider, raw)` — generic fallback, tries both OpenAI-style (`prompt_tokens`) and Anthropic-style (`input_tokens`) conventions

### Provider Mapping Table

| Normalized Field | OpenAI | Anthropic | OpenRouter | Fallback |
|---|---|---|---|---|
| `input_tokens` | `prompt_tokens` | `input_tokens` | `prompt_tokens` | `input_tokens` \|\| `prompt_tokens` |
| `output_tokens` | `completion_tokens` | `output_tokens` | `completion_tokens` | `output_tokens` \|\| `completion_tokens` |
| `total_tokens` | `total_tokens` | calculated | `total_tokens` | `total_tokens` \|\| calculated |
| `cache_read_tokens` | nil | `cache_read_input_tokens` | nil | `cache_read_input_tokens` |
| `cache_creation_tokens` | nil | `cache_creation_input_tokens` | nil | `cache_creation_input_tokens` |
| `provider_specific` | raw map | raw map | raw map | raw map |

### Design Decisions

1. **Multi-clause pattern matching** — idiomatic Elixir, all normalization logic in one module
2. **Explicit atom dispatch** — consistent with `Error` struct pattern (`:openai`, `:anthropic`, `:openrouter`)
3. **Generic fallback** — unknown providers work automatically if they use OpenAI-compatible or Anthropic-compatible wire format
4. **Zero-valued default** — nil/empty input returns `%Usage{}` with all zeros, consumers never need nil checks on `Response.usage`
5. **Public API** — consumers creating custom providers can use `from_provider/2` directly

## Components

### Files to Create

- `lib/phoenix_ai/usage.ex` — struct + `from_provider/2`
- `test/phoenix_ai/usage_test.exs` — comprehensive test suite

### Files NOT Modified (Phase 12 scope)

- `lib/phoenix_ai/response.ex` — change `usage: map()` → `usage: Usage.t()`
- `lib/phoenix_ai/stream_chunk.ex` — change `usage: map() | nil` → `usage: Usage.t() | nil`
- `lib/phoenix_ai/providers/openai.ex` — call `Usage.from_provider(:openai, raw)`
- `lib/phoenix_ai/providers/anthropic.ex` — call `Usage.from_provider(:anthropic, raw)`
- `lib/phoenix_ai/providers/openrouter.ex` — call `Usage.from_provider(:openrouter, raw)`
- `lib/phoenix_ai/stream.ex` — update accumulator logic

## Testing Strategy

### Test File: `test/phoenix_ai/usage_test.exs`

**Per-provider groups:**

1. **OpenAI:**
   - Maps `prompt_tokens` → `input_tokens`, `completion_tokens` → `output_tokens`
   - Preserves provider's `total_tokens`
   - `cache_*` fields are nil
   - `provider_specific` holds raw map

2. **Anthropic:**
   - Maps `input_tokens` directly
   - Auto-calculates `total_tokens` as `input + output`
   - Maps `cache_read_input_tokens` → `cache_read_tokens`
   - Maps `cache_creation_input_tokens` → `cache_creation_tokens`
   - `provider_specific` holds raw map

3. **OpenRouter:**
   - Same mapping as OpenAI
   - Preserves extra fields (`native_tokens_prompt`, etc.) in `provider_specific`

**Edge cases:**
- `nil` input → zero `%Usage{}`
- `%{}` input → zero `%Usage{}`
- Unknown provider with OpenAI-compatible format → fallback works
- Unknown provider with Anthropic-style format → fallback works
- Partial fields (e.g., only `prompt_tokens`, no `completion_tokens`) → zeros for missing

**Invariants:**
- `provider_specific` always contains the raw map
- `total_tokens == input_tokens + output_tokens` when auto-calculated
- `cache_*` is nil for OpenAI/OpenRouter, can be integer for Anthropic

## Error Handling

None. `from_provider/2` is a pure transformation that always succeeds. No `{:ok, _}` / `{:error, _}` wrapping. Invalid input produces a valid (possibly zero-valued) struct.

## Scope Boundary

This phase creates the Usage struct and factory in isolation. It does NOT:
- Modify `Response` or `StreamChunk` structs (Phase 12)
- Modify provider adapters (Phase 12)
- Modify `Stream.ex` accumulator logic (Phase 12)
- Add cost calculation helpers (out of scope)

---
*Design approved: 2026-04-03*
