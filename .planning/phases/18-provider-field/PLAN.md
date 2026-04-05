# Provider Field Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `:provider` field to `%PhoenixAI.Response{}` so downstream consumers can identify the originating provider atom.

**Architecture:** Each provider adapter sets `provider: :atom` in the `%Response{}` it constructs inside `parse_response/1`. TestProvider changes from passthrough to merge. Backward compatible — defaults to `nil`.

**Tech Stack:** Elixir, ExUnit

**Spec:** `.planning/phases/18-provider-field/BRAINSTORM.md`

---

## File Structure

| Action | File | Responsibility |
|--------|------|----------------|
| Modify | `lib/phoenix_ai/response.ex` | Add `:provider` to defstruct and @type |
| Modify | `lib/phoenix_ai/providers/openai.ex` | Set `provider: :openai` in parse_response |
| Modify | `lib/phoenix_ai/providers/anthropic.ex` | Set `provider: :anthropic` in parse_response |
| Modify | `lib/phoenix_ai/providers/openrouter.ex` | Set `provider: :openrouter` in parse_response |
| Modify | `lib/phoenix_ai/providers/test_provider.ex` | Change parse_response from passthrough to merge |
| Modify | `test/phoenix_ai/providers/openai_test.exs` | Assert `response.provider == :openai` |
| Modify | `test/phoenix_ai/providers/anthropic_test.exs` | Assert `response.provider == :anthropic` |
| Modify | `test/phoenix_ai/providers/openrouter_test.exs` | Assert `response.provider == :openrouter` |
| Modify | `test/phoenix_ai/providers/test_provider_test.exs` | Assert `response.provider == :test` |
| Modify | `mix.exs` | Bump version to 0.3.1 |

---

### Task 1: Add `:provider` field to Response struct

**Files:**
- Modify: `lib/phoenix_ai/response.ex`

- [ ] **Step 1: Add `:provider` to `@type t` and `defstruct`**

Replace the entire `response.ex` content with:

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
end
```

- [ ] **Step 2: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Compiles cleanly with no warnings.

- [ ] **Step 3: Run existing tests to confirm no regressions**

Run: `mix test`
Expected: All 421 tests pass. The new `nil` default means nothing breaks.

- [ ] **Step 4: Commit**

```bash
git add lib/phoenix_ai/response.ex
git commit -m "feat(response): add :provider field to Response struct"
```

---

### Task 2: Set `:provider` in OpenAI adapter + test

**Files:**
- Modify: `lib/phoenix_ai/providers/openai.ex:60-66`
- Modify: `test/phoenix_ai/providers/openai_test.exs:13-26`

- [ ] **Step 1: Write the failing test**

In `test/phoenix_ai/providers/openai_test.exs`, add this assertion inside the existing `"parses a simple chat completion"` test, after line 25 (`assert response.provider_response == fixture`):

```elixir
      assert response.provider == :openai
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/phoenix_ai/providers/openai_test.exs:14 --trace`
Expected: FAIL — `assert response.provider == :openai` fails because `response.provider` is `nil`.

- [ ] **Step 3: Set `provider: :openai` in `parse_response/1`**

In `lib/phoenix_ai/providers/openai.ex`, inside the `%Response{}` struct literal in `parse_response/1` (~line 60), add `provider: :openai` after the `model: model` line:

```elixir
    %Response{
      content: content,
      finish_reason: finish_reason,
      model: model,
      provider: :openai,
      usage: usage,
      tool_calls: tool_calls,
      provider_response: body
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/phoenix_ai/providers/openai_test.exs --trace`
Expected: All OpenAI tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_ai/providers/openai.ex test/phoenix_ai/providers/openai_test.exs
git commit -m "feat(openai): set provider: :openai in parse_response/1"
```

---

### Task 3: Set `:provider` in Anthropic adapter + test

**Files:**
- Modify: `lib/phoenix_ai/providers/anthropic.ex:213-219`
- Modify: `test/phoenix_ai/providers/anthropic_test.exs:13-26`

- [ ] **Step 1: Write the failing test**

In `test/phoenix_ai/providers/anthropic_test.exs`, add this assertion inside the existing `"parses a simple chat completion"` test, after `assert response.provider_response == fixture`:

```elixir
      assert response.provider == :anthropic
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/phoenix_ai/providers/anthropic_test.exs:14 --trace`
Expected: FAIL — `response.provider` is `nil`.

- [ ] **Step 3: Set `provider: :anthropic` in `parse_response/1`**

In `lib/phoenix_ai/providers/anthropic.ex`, inside the `%Response{}` struct literal in `parse_response/1` (~line 213), add `provider: :anthropic` after the `model: model` line:

```elixir
    %Response{
      content: final_content,
      finish_reason: stop_reason,
      model: model,
      provider: :anthropic,
      usage: usage,
      tool_calls: tool_calls,
      provider_response: body
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/phoenix_ai/providers/anthropic_test.exs --trace`
Expected: All Anthropic tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_ai/providers/anthropic.ex test/phoenix_ai/providers/anthropic_test.exs
git commit -m "feat(anthropic): set provider: :anthropic in parse_response/1"
```

---

### Task 4: Set `:provider` in OpenRouter adapter + test

**Files:**
- Modify: `lib/phoenix_ai/providers/openrouter.ex:36-42`
- Modify: `test/phoenix_ai/providers/openrouter_test.exs:13-26`

- [ ] **Step 1: Write the failing test**

In `test/phoenix_ai/providers/openrouter_test.exs`, add this assertion inside the existing `"parses a simple chat completion"` test, after `assert response.provider_response == fixture`:

```elixir
      assert response.provider == :openrouter
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/phoenix_ai/providers/openrouter_test.exs:14 --trace`
Expected: FAIL — `response.provider` is `nil`.

- [ ] **Step 3: Set `provider: :openrouter` in `parse_response/1`**

In `lib/phoenix_ai/providers/openrouter.ex`, inside the `%Response{}` struct literal in `parse_response/1` (~line 36), add `provider: :openrouter` after the `model: model` line:

```elixir
    %Response{
      content: content,
      finish_reason: finish_reason,
      model: model,
      provider: :openrouter,
      usage: usage,
      tool_calls: tool_calls,
      provider_response: body
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/phoenix_ai/providers/openrouter_test.exs --trace`
Expected: All OpenRouter tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_ai/providers/openrouter.ex test/phoenix_ai/providers/openrouter_test.exs
git commit -m "feat(openrouter): set provider: :openrouter in parse_response/1"
```

---

### Task 5: Set `:provider` in TestProvider adapter + test

**Files:**
- Modify: `lib/phoenix_ai/providers/test_provider.ex:94`
- Modify: `test/phoenix_ai/providers/test_provider_test.exs`

- [ ] **Step 1: Write the failing test**

In `test/phoenix_ai/providers/test_provider_test.exs`, add a new test inside the `"chat/2 — queue mode"` describe block, after the existing tests:

```elixir
    test "parse_response/1 sets provider to :test" do
      body = %Response{content: "hello"}
      result = TestProvider.parse_response(body)

      assert result.provider == :test
      assert result.content == "hello"
    end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/phoenix_ai/providers/test_provider_test.exs --trace`
Expected: FAIL — `result.provider` is `nil` because `parse_response/1` is a passthrough.

- [ ] **Step 3: Change `parse_response/1` from passthrough to merge**

In `lib/phoenix_ai/providers/test_provider.ex`, line 94, change:

```elixir
  def parse_response(body), do: body
```

to:

```elixir
  def parse_response(body), do: %{body | provider: :test}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/phoenix_ai/providers/test_provider_test.exs --trace`
Expected: All TestProvider tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_ai/providers/test_provider.ex test/phoenix_ai/providers/test_provider_test.exs
git commit -m "feat(test_provider): set provider: :test in parse_response/1"
```

---

### Task 6: Version bump + full test suite

**Files:**
- Modify: `mix.exs:4`

- [ ] **Step 1: Bump version in mix.exs**

In `mix.exs`, line 4, change:

```elixir
  @version "0.3.0"
```

to:

```elixir
  @version "0.3.1"
```

- [ ] **Step 2: Run full test suite**

Run: `mix test`
Expected: All tests pass (421 existing + 4 new assertions = all green).

- [ ] **Step 3: Run formatter**

Run: `mix format --check-formatted`
Expected: No formatting issues.

- [ ] **Step 4: Commit**

```bash
git add mix.exs
git commit -m "chore: bump version to 0.3.1"
```
