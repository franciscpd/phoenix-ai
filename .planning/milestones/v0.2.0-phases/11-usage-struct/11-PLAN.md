# PhoenixAI.Usage Struct Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create `PhoenixAI.Usage` struct with `from_provider/2` factory that normalizes raw provider usage maps into a consistent shape.

**Architecture:** Single module `PhoenixAI.Usage` with struct definition and multi-clause `from_provider/2` using explicit atom dispatch per provider plus a generic fallback. Pure transformation — no side effects, no error tuples.

**Tech Stack:** Elixir, ExUnit

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `lib/phoenix_ai/usage.ex` | Create | Struct definition + `from_provider/2` factory |
| `test/phoenix_ai/usage_test.exs` | Create | Full test suite covering all providers, edge cases, and invariants |

---

### Task 1: Usage Struct Definition + OpenAI Mapping

**Files:**
- Create: `test/phoenix_ai/usage_test.exs`
- Create: `lib/phoenix_ai/usage.ex`

- [ ] **Step 1: Write failing tests for struct and OpenAI mapping**

```elixir
defmodule PhoenixAI.UsageTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Usage

  describe "struct" do
    test "has expected default values" do
      usage = %Usage{}
      assert usage.input_tokens == 0
      assert usage.output_tokens == 0
      assert usage.total_tokens == 0
      assert usage.cache_read_tokens == nil
      assert usage.cache_creation_tokens == nil
      assert usage.provider_specific == %{}
    end
  end

  describe "from_provider/2 with :openai" do
    test "maps OpenAI usage fields to normalized struct" do
      raw = %{
        "prompt_tokens" => 150,
        "completion_tokens" => 80,
        "total_tokens" => 230
      }

      usage = Usage.from_provider(:openai, raw)

      assert usage.input_tokens == 150
      assert usage.output_tokens == 80
      assert usage.total_tokens == 230
      assert usage.cache_read_tokens == nil
      assert usage.cache_creation_tokens == nil
      assert usage.provider_specific == raw
    end

    test "auto-calculates total_tokens when provider returns 0" do
      raw = %{
        "prompt_tokens" => 100,
        "completion_tokens" => 50,
        "total_tokens" => 0
      }

      usage = Usage.from_provider(:openai, raw)
      assert usage.total_tokens == 150
    end

    test "handles missing fields with zero defaults" do
      raw = %{"prompt_tokens" => 42}

      usage = Usage.from_provider(:openai, raw)

      assert usage.input_tokens == 42
      assert usage.output_tokens == 0
      assert usage.total_tokens == 42
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_ai/usage_test.exs`
Expected: FAIL — module `PhoenixAI.Usage` is not available

- [ ] **Step 3: Implement struct and OpenAI clause**

```elixir
defmodule PhoenixAI.Usage do
  @moduledoc """
  Normalized token usage from any AI provider.

  All provider-specific usage data is mapped to a consistent shape
  via `from_provider/2`. The original raw data is preserved in
  `provider_specific` for backward compatibility.

  ## Examples

      iex> PhoenixAI.Usage.from_provider(:openai, %{"prompt_tokens" => 10, "completion_tokens" => 20, "total_tokens" => 30})
      %PhoenixAI.Usage{input_tokens: 10, output_tokens: 20, total_tokens: 30, provider_specific: %{"prompt_tokens" => 10, "completion_tokens" => 20, "total_tokens" => 30}}

  """

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

  @doc """
  Maps raw provider usage data to a normalized `%Usage{}` struct.

  Accepts a provider atom and the raw usage map from the provider's
  JSON response. Returns a `%Usage{}` with consistent field names.

  ## Supported providers

    * `:openai` — maps `prompt_tokens`, `completion_tokens`, `total_tokens`
    * `:anthropic` — maps `input_tokens`, `output_tokens`, cache fields; auto-calculates `total_tokens`
    * `:openrouter` — delegates to `:openai` (same wire format)
    * Any other atom — generic fallback that tries both naming conventions

  When `raw` is `nil` or an empty map, returns a zero-valued `%Usage{}`.
  """
  @spec from_provider(atom(), map() | nil) :: t()
  def from_provider(:openai, raw) when is_map(raw) do
    input = Map.get(raw, "prompt_tokens", 0)
    output = Map.get(raw, "completion_tokens", 0)
    total = Map.get(raw, "total_tokens", 0)

    %__MODULE__{
      input_tokens: input,
      output_tokens: output,
      total_tokens: if(total == 0, do: input + output, else: total),
      provider_specific: raw
    }
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/phoenix_ai/usage_test.exs`
Expected: 4 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_ai/usage.ex test/phoenix_ai/usage_test.exs
git commit -m "feat(usage): add Usage struct and OpenAI mapping"
```

---

### Task 2: Anthropic Mapping

**Files:**
- Modify: `test/phoenix_ai/usage_test.exs`
- Modify: `lib/phoenix_ai/usage.ex`

- [ ] **Step 1: Write failing tests for Anthropic mapping**

Add to `test/phoenix_ai/usage_test.exs`:

```elixir
describe "from_provider/2 with :anthropic" do
  test "maps Anthropic usage fields to normalized struct" do
    raw = %{
      "input_tokens" => 150,
      "output_tokens" => 80,
      "cache_creation_input_tokens" => 20,
      "cache_read_input_tokens" => 10
    }

    usage = Usage.from_provider(:anthropic, raw)

    assert usage.input_tokens == 150
    assert usage.output_tokens == 80
    assert usage.total_tokens == 230
    assert usage.cache_read_tokens == 10
    assert usage.cache_creation_tokens == 20
    assert usage.provider_specific == raw
  end

  test "auto-calculates total_tokens" do
    raw = %{"input_tokens" => 100, "output_tokens" => 50}

    usage = Usage.from_provider(:anthropic, raw)
    assert usage.total_tokens == 150
  end

  test "cache fields are nil when not present" do
    raw = %{"input_tokens" => 100, "output_tokens" => 50}

    usage = Usage.from_provider(:anthropic, raw)

    assert usage.cache_read_tokens == nil
    assert usage.cache_creation_tokens == nil
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_ai/usage_test.exs`
Expected: FAIL — no function clause matching

- [ ] **Step 3: Add Anthropic clause to `from_provider/2`**

Add to `lib/phoenix_ai/usage.ex` after the OpenAI clause:

```elixir
def from_provider(:anthropic, raw) when is_map(raw) do
  input = Map.get(raw, "input_tokens", 0)
  output = Map.get(raw, "output_tokens", 0)

  %__MODULE__{
    input_tokens: input,
    output_tokens: output,
    total_tokens: input + output,
    cache_read_tokens: Map.get(raw, "cache_read_input_tokens"),
    cache_creation_tokens: Map.get(raw, "cache_creation_input_tokens"),
    provider_specific: raw
  }
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/phoenix_ai/usage_test.exs`
Expected: 7 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_ai/usage.ex test/phoenix_ai/usage_test.exs
git commit -m "feat(usage): add Anthropic mapping with cache fields"
```

---

### Task 3: OpenRouter Delegation + Nil/Empty Handling + Generic Fallback

**Files:**
- Modify: `test/phoenix_ai/usage_test.exs`
- Modify: `lib/phoenix_ai/usage.ex`

- [ ] **Step 1: Write failing tests for OpenRouter, nil/empty, and fallback**

Add to `test/phoenix_ai/usage_test.exs`:

```elixir
describe "from_provider/2 with :openrouter" do
  test "delegates to OpenAI mapping" do
    raw = %{
      "prompt_tokens" => 150,
      "completion_tokens" => 80,
      "total_tokens" => 230,
      "native_tokens_prompt" => 145,
      "native_tokens_completion" => 78
    }

    usage = Usage.from_provider(:openrouter, raw)

    assert usage.input_tokens == 150
    assert usage.output_tokens == 80
    assert usage.total_tokens == 230
    assert usage.provider_specific == raw
  end
end

describe "from_provider/2 with nil and empty map" do
  test "nil returns zero-valued usage" do
    usage = Usage.from_provider(:openai, nil)

    assert usage.input_tokens == 0
    assert usage.output_tokens == 0
    assert usage.total_tokens == 0
    assert usage.cache_read_tokens == nil
    assert usage.cache_creation_tokens == nil
    assert usage.provider_specific == %{}
  end

  test "empty map returns zero-valued usage" do
    usage = Usage.from_provider(:openai, %{})

    assert usage.input_tokens == 0
    assert usage.output_tokens == 0
    assert usage.total_tokens == 0
    assert usage.provider_specific == %{}
  end
end

describe "from_provider/2 with unknown provider" do
  test "fallback handles OpenAI-compatible format" do
    raw = %{
      "prompt_tokens" => 100,
      "completion_tokens" => 50,
      "total_tokens" => 150
    }

    usage = Usage.from_provider(:groq, raw)

    assert usage.input_tokens == 100
    assert usage.output_tokens == 50
    assert usage.total_tokens == 150
    assert usage.provider_specific == raw
  end

  test "fallback handles Anthropic-style format" do
    raw = %{
      "input_tokens" => 100,
      "output_tokens" => 50,
      "cache_read_input_tokens" => 5
    }

    usage = Usage.from_provider(:custom, raw)

    assert usage.input_tokens == 100
    assert usage.output_tokens == 50
    assert usage.total_tokens == 150
    assert usage.cache_read_tokens == 5
    assert usage.provider_specific == raw
  end

  test "fallback auto-calculates total_tokens when missing" do
    raw = %{"prompt_tokens" => 30, "completion_tokens" => 20}

    usage = Usage.from_provider(:together, raw)
    assert usage.total_tokens == 50
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_ai/usage_test.exs`
Expected: FAIL — no function clause matching for `:openrouter`, nil, fallback

- [ ] **Step 3: Add OpenRouter, nil/empty, and fallback clauses**

Add to `lib/phoenix_ai/usage.ex` after the Anthropic clause:

```elixir
def from_provider(:openrouter, raw), do: from_provider(:openai, raw)

def from_provider(_provider, nil), do: %__MODULE__{}
def from_provider(_provider, raw) when raw == %{}, do: %__MODULE__{}

def from_provider(_provider, raw) when is_map(raw) do
  input = Map.get(raw, "input_tokens") || Map.get(raw, "prompt_tokens") || 0
  output = Map.get(raw, "output_tokens") || Map.get(raw, "completion_tokens") || 0
  total = Map.get(raw, "total_tokens") || input + output

  %__MODULE__{
    input_tokens: input,
    output_tokens: output,
    total_tokens: total,
    cache_read_tokens: Map.get(raw, "cache_read_input_tokens"),
    cache_creation_tokens: Map.get(raw, "cache_creation_input_tokens"),
    provider_specific: raw
  }
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/phoenix_ai/usage_test.exs`
Expected: 14 tests, 0 failures

- [ ] **Step 5: Run full test suite to verify no regressions**

Run: `mix test`
Expected: All tests pass (311 existing + 14 new = 325)

- [ ] **Step 6: Run code quality checks**

Run: `mix format --check-formatted && mix credo --strict`
Expected: No formatting issues, no credo warnings

- [ ] **Step 7: Commit**

```bash
git add lib/phoenix_ai/usage.ex test/phoenix_ai/usage_test.exs
git commit -m "feat(usage): add OpenRouter, nil/empty, and generic fallback"
```

---

## Verification Checklist

After all tasks complete, verify:

- [ ] `PhoenixAI.Usage` struct exists with all 6 fields
- [ ] `from_provider(:openai, raw)` maps correctly
- [ ] `from_provider(:anthropic, raw)` maps correctly with cache fields
- [ ] `from_provider(:openrouter, raw)` delegates to `:openai`
- [ ] `from_provider(_, nil)` and `from_provider(_, %{})` return zero usage
- [ ] `from_provider(:unknown, raw)` fallback works with both conventions
- [ ] `total_tokens` auto-calculated when provider doesn't return it
- [ ] `provider_specific` preserves raw map in all cases
- [ ] All existing 311 tests still pass
- [ ] `mix format` and `mix credo --strict` pass
