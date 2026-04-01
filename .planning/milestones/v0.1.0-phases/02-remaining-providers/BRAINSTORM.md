# Phase 2: Remaining Providers — Design Spec

**Date:** 2026-03-29
**Phase:** 02-remaining-providers
**Status:** Approved
**Approach:** A — Adapters first, dispatch last

## Overview

Add Anthropic and OpenRouter provider adapters to complete the v1 multi-provider support. Each adapter is fully independent (no code sharing between adapters). Contract tests verify all adapters produce consistent `%Response{}` output.

**Requirements covered:** PROV-02, PROV-03, PROV-05, PROV-06

## Architecture

### Component Diagram

```
AI.chat/2 (dispatch — already exists)
├── resolve_provider/1 → {:ok, module}
├── Config.resolve/2 → merged opts
└── provider_mod.chat/2
    ├── PhoenixAI.Providers.OpenAI    (Phase 1 — exists)
    ├── PhoenixAI.Providers.Anthropic  (NEW)
    └── PhoenixAI.Providers.OpenRouter (NEW)
```

### Data Flow

```
caller → AI.chat(messages, provider: :anthropic)
  → Config.resolve(:anthropic, opts) — cascades call-site > config > env > defaults
  → Providers.Anthropic.chat(messages, merged_opts)
    → extract system messages from list
    → format_messages (user/assistant only)
    → build body {model, system, messages, ...}
    → Req.post("https://api.anthropic.com/v1/messages", ...)
    → parse_response(body) → %Response{}
  → {:ok, %Response{}}
```

## Components

### 1. Anthropic Adapter (`lib/phoenix_ai/providers/anthropic.ex`)

Implements `PhoenixAI.Provider` behaviour for Anthropic's Messages API.

**Key differences from OpenAI:**

| Aspect | OpenAI | Anthropic |
|--------|--------|-----------|
| Auth header | `Authorization: Bearer {key}` | `x-api-key: {key}` |
| Version header | None | `anthropic-version: 2023-06-01` |
| System message | `role: "system"` in messages array | Top-level `system` param |
| Response content | `choices[0].message.content` (string) | `content[0].text` (content blocks array) |
| Stop signal | `finish_reason: "stop"` | `stop_reason: "end_turn"` |
| Usage keys | `prompt_tokens`, `completion_tokens` | `input_tokens`, `output_tokens` |
| Tool calls | `choices[0].message.tool_calls[]` | `content[].type == "tool_use"` blocks |

**Public API:**

```elixir
@behaviour PhoenixAI.Provider

@impl true
def chat(messages, opts)
# Extracts :system messages automatically from message list
# Places as top-level "system" param in request body
# Returns {:ok, %Response{}} | {:error, %Error{}}

@impl true
def parse_response(body)
# Maps Anthropic response format to canonical %Response{}
# Normalizes content blocks, stop_reason, usage, tool_use
```

**System message handling:**
- `Enum.split_with(messages, &(&1.role == :system))` to extract system messages
- Multiple system messages concatenated with `\n\n`
- Empty system list → omit `system` key from body entirely

**finish_reason normalization:**
- `stop_reason` from Anthropic is mapped to `finish_reason` in `%Response{}` **preserving the original value** (e.g., `"end_turn"`, `"tool_use"`) — no cross-provider normalization. Consumers who need provider-agnostic logic should check `provider_response` or handle both formats.

**Tool call parsing (Phase 2 scope — parse only, don't execute):**
- Filter `content` blocks where `type == "tool_use"`
- Map to `%ToolCall{id: id, name: name, arguments: input}`
- Non-tool content blocks (`type == "text"`) map to `Response.content`

### 2. OpenRouter Adapter (`lib/phoenix_ai/providers/openrouter.ex`)

Implements `PhoenixAI.Provider` behaviour. OpenAI-compatible API, fully independent code.

**Key differences from OpenAI:**

| Aspect | OpenAI | OpenRouter |
|--------|--------|------------|
| Base URL | `https://api.openai.com/v1` | `https://openrouter.ai/api/v1` |
| Default model | `gpt-4o` | **None** — `:model_required` error |
| Optional headers | None | `HTTP-Referer`, `X-Title` via provider_options |
| Response format | Identical | Identical |
| Message format | Identical | Identical |

**Public API:**

```elixir
@behaviour PhoenixAI.Provider

@impl true
def chat(messages, opts)
# Validates model: is present (returns {:error, :model_required} if not)
# Injects HTTP-Referer/X-Title from provider_options if present
# Returns {:ok, %Response{}} | {:error, %Error{}}

@impl true
def parse_response(body)
# Identical logic to OpenAI (same response format)
# But implemented independently — no delegation
```

**Model validation:**
- Check `Keyword.get(opts, :model)` before building request
- If `nil`: `{:error, %Error{status: nil, message: "model is required for OpenRouter", provider: :openrouter}}`

**Optional headers from provider_options:**
- `provider_options["http_referer"]` → `HTTP-Referer` header
- `provider_options["x_title"]` → `X-Title` header
- Only sent if explicitly provided — no defaults

### 3. Config — No Changes Required

The existing `PhoenixAI.Config` module already handles `:anthropic` and `:openrouter`:
- `@env_vars` has `ANTHROPIC_API_KEY` and `OPENROUTER_API_KEY`
- `@default_models` has `anthropic: "claude-sonnet-4-5"` — no entry for `:openrouter` (returns `nil`, which means no default — correct behavior)
- `Config.resolve/2` works for any provider atom

The `:model_required` validation lives in `Providers.OpenRouter.chat/2`, not in Config.

### 4. AI Module — No Changes Required

The dispatch in `AI` already:
- Maps `:anthropic` → `PhoenixAI.Providers.Anthropic`
- Maps `:openrouter` → `PhoenixAI.Providers.OpenRouter`
- Uses `Code.ensure_loaded?/1` to check if module exists
- Returns `{:error, {:provider_not_implemented, atom}}` for known but unloaded providers

Once the adapter modules exist, the dispatch "just works". The existing test `assert {:error, {:provider_not_implemented, :anthropic}}` will need updating to expect `{:ok, _}` once the adapter exists.

## Testing Strategy

### Approach: Adapters first, contracts last

1. Anthropic adapter + unit tests with fixtures
2. OpenRouter adapter + unit tests with fixtures
3. Contract tests verifying all 3 adapters
4. Update existing AI dispatch tests

### Fixtures

**`test/support/fixtures/anthropic/`**

- `messages_completion.json` — Standard Messages API response:
  ```json
  {
    "id": "msg_...",
    "type": "message",
    "role": "assistant",
    "content": [{"type": "text", "text": "Hello!"}],
    "model": "claude-sonnet-4-5-20250514",
    "stop_reason": "end_turn",
    "usage": {"input_tokens": 10, "output_tokens": 5}
  }
  ```

- `messages_with_tool_use.json` — Response with tool_use content block:
  ```json
  {
    "content": [
      {"type": "text", "text": "Let me check..."},
      {"type": "tool_use", "id": "toolu_abc", "name": "get_weather", "input": {"city": "Lisbon"}}
    ],
    "stop_reason": "tool_use"
  }
  ```

- `messages_error_401.json` — Auth error response

**`test/support/fixtures/openrouter/`**

- `chat_completion.json` — Standard response (OpenAI format)
- `chat_error_401.json` — Auth error response

### Unit Tests

**`test/phoenix_ai/providers/anthropic_test.exs`**

- `parse_response/1`:
  - Parses simple text completion → `%Response{content: "Hello!"}`
  - Parses tool_use blocks → `%Response{tool_calls: [%ToolCall{}]}`
  - Extracts text content alongside tool_use → both populated
  - Maps `stop_reason` to `finish_reason`
  - Normalizes usage keys (`input_tokens` → kept as-is in usage map)
  - Preserves raw response in `provider_response`

- `format_messages/1`:
  - Extracts system messages from list (not included in formatted output)
  - Maps user/assistant messages correctly
  - Handles empty system message list

**`test/phoenix_ai/providers/openrouter_test.exs`**

- `parse_response/1`:
  - Parses standard chat completion (same assertions as OpenAI)
  - Parses tool calls

- `chat/2` validation:
  - Returns `{:error, %Error{message: "model is required..."}}` when model is nil

### Contract Tests

**`test/phoenix_ai/providers/provider_contract_test.exs`**

Cross-adapter consistency verification:

```elixir
for {provider, fixture_dir, fixture_file} <- [
  {PhoenixAI.Providers.OpenAI, "openai", "chat_completion.json"},
  {PhoenixAI.Providers.Anthropic, "anthropic", "messages_completion.json"},
  {PhoenixAI.Providers.OpenRouter, "openrouter", "chat_completion.json"}
] do
  describe "#{provider} contract" do
    test "parse_response returns %Response{} with all expected fields" do
      fixture = load_fixture(fixture_dir, fixture_file)
      response = provider.parse_response(fixture)

      assert %Response{} = response
      assert is_binary(response.content) or is_nil(response.content)
      assert is_list(response.tool_calls)
      assert is_map(response.usage)
      assert is_binary(response.finish_reason) or is_nil(response.finish_reason)
      assert is_binary(response.model) or is_nil(response.model)
      assert is_map(response.provider_response)
    end
  end
end
```

### Updated AI Tests

- Remove/update `{:error, {:provider_not_implemented, :anthropic}}` test — now it resolves
- Add test: `AI.chat(messages, provider: :anthropic, api_key: "key")` delegates to Anthropic adapter (via Mox)
- Add test: `AI.chat(messages, provider: :openrouter, api_key: "key", model: "...")` delegates to OpenRouter adapter

## Error Handling

All adapters follow the same error pattern established by OpenAI:

```elixir
# HTTP error
{:error, %Error{status: 401, message: "...", provider: :anthropic}}

# Network/transport error
{:error, %Error{status: nil, message: "...", provider: :openrouter}}

# Missing API key (from AI.chat/2 dispatch)
{:error, {:missing_api_key, :anthropic}}

# OpenRouter-specific: missing model
{:error, %Error{status: nil, message: "model is required for OpenRouter", provider: :openrouter}}
```

## Files Changed

| File | Action | Description |
|------|--------|-------------|
| `lib/phoenix_ai/providers/anthropic.ex` | Create | Anthropic Messages API adapter |
| `lib/phoenix_ai/providers/openrouter.ex` | Create | OpenRouter adapter (OpenAI-compatible, independent) |
| `test/phoenix_ai/providers/anthropic_test.exs` | Create | Anthropic adapter unit tests |
| `test/phoenix_ai/providers/openrouter_test.exs` | Create | OpenRouter adapter unit tests |
| `test/phoenix_ai/providers/provider_contract_test.exs` | Create | Cross-adapter contract tests |
| `test/support/fixtures/anthropic/*.json` | Create | Anthropic API response fixtures |
| `test/support/fixtures/openrouter/*.json` | Create | OpenRouter API response fixtures |
| `test/phoenix_ai/ai_test.exs` | Modify | Update dispatch tests for now-available providers |

**No changes to:** `lib/ai.ex`, `lib/phoenix_ai/config.ex`, `lib/phoenix_ai/provider.ex`

## Success Criteria (from ROADMAP.md)

1. `PhoenixAI.chat(messages, provider: :anthropic, model: "claude-opus-4-5")` returns `{:ok, %Response{}}`
2. `PhoenixAI.chat(messages, provider: :openrouter, model: "...")` returns `{:ok, %Response{}}`
3. `PhoenixAI.chat/2` resolves the correct adapter from the `provider:` option
4. Provider-specific parameters pass through via `provider_options: %{...}`
5. Unknown provider returns `{:error, {:unknown_provider, atom}}`

---

*Design approved: 2026-03-29*
*Approach: A — Adapters first, dispatch last*
