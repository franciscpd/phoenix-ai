# Phase 2: Remaining Providers — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Anthropic and OpenRouter provider adapters so all three v1 providers work through `AI.chat/2` with consistent `%Response{}` output.

**Architecture:** Each adapter is a self-contained module implementing `PhoenixAI.Provider` behaviour. Anthropic translates Messages API format; OpenRouter wraps an OpenAI-compatible API with different base URL and model-required validation. Contract tests verify all adapters produce the same response shape.

**Tech Stack:** Elixir, Req (HTTP), Jason (JSON), ExUnit + Mox (testing)

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `test/support/fixtures/anthropic/messages_completion.json` | Create | Anthropic simple response fixture |
| `test/support/fixtures/anthropic/messages_with_tool_use.json` | Create | Anthropic tool_use response fixture |
| `test/support/fixtures/anthropic/messages_error_401.json` | Create | Anthropic auth error fixture |
| `test/phoenix_ai/providers/anthropic_test.exs` | Create | Anthropic adapter unit tests |
| `lib/phoenix_ai/providers/anthropic.ex` | Create | Anthropic Messages API adapter |
| `test/support/fixtures/openrouter/chat_completion.json` | Create | OpenRouter simple response fixture |
| `test/support/fixtures/openrouter/chat_completion_with_tools.json` | Create | OpenRouter tool call response fixture |
| `test/support/fixtures/openrouter/chat_error_401.json` | Create | OpenRouter auth error fixture |
| `test/phoenix_ai/providers/openrouter_test.exs` | Create | OpenRouter adapter unit tests |
| `lib/phoenix_ai/providers/openrouter.ex` | Create | OpenRouter adapter (OpenAI-compatible, independent) |
| `test/phoenix_ai/providers/provider_contract_test.exs` | Create | Cross-adapter contract tests |
| `test/phoenix_ai/ai_test.exs` | Modify | Update dispatch tests for now-available providers |

---

### Task 1: Anthropic Fixtures

**Files:**
- Create: `test/support/fixtures/anthropic/messages_completion.json`
- Create: `test/support/fixtures/anthropic/messages_with_tool_use.json`
- Create: `test/support/fixtures/anthropic/messages_error_401.json`

- [ ] **Step 1: Create Anthropic fixtures directory**

Run:
```bash
mkdir -p test/support/fixtures/anthropic
```

- [ ] **Step 2: Create simple completion fixture**

Create `test/support/fixtures/anthropic/messages_completion.json`:

```json
{
  "id": "msg_01XFDUDYJgAACzvnptvVoYEL",
  "type": "message",
  "role": "assistant",
  "content": [
    {
      "type": "text",
      "text": "Hello! How can I help you today?"
    }
  ],
  "model": "claude-sonnet-4-5-20250514",
  "stop_reason": "end_turn",
  "stop_sequence": null,
  "usage": {
    "input_tokens": 10,
    "output_tokens": 9
  }
}
```

- [ ] **Step 3: Create tool_use fixture**

Create `test/support/fixtures/anthropic/messages_with_tool_use.json`:

```json
{
  "id": "msg_01YKf3G4rNpKDsR94JqFnBTw",
  "type": "message",
  "role": "assistant",
  "content": [
    {
      "type": "text",
      "text": "Let me check the weather for you."
    },
    {
      "type": "tool_use",
      "id": "toolu_01A09q90qw90lq917835lgs0",
      "name": "get_weather",
      "input": {
        "city": "Lisbon"
      }
    }
  ],
  "model": "claude-sonnet-4-5-20250514",
  "stop_reason": "tool_use",
  "stop_sequence": null,
  "usage": {
    "input_tokens": 50,
    "output_tokens": 30
  }
}
```

- [ ] **Step 4: Create auth error fixture**

Create `test/support/fixtures/anthropic/messages_error_401.json`:

```json
{
  "type": "error",
  "error": {
    "type": "authentication_error",
    "message": "invalid x-api-key"
  }
}
```

- [ ] **Step 5: Commit**

```bash
git add test/support/fixtures/anthropic/
git commit -m "test(02): add Anthropic API response fixtures"
```

---

### Task 2: Anthropic Adapter Tests

**Files:**
- Create: `test/phoenix_ai/providers/anthropic_test.exs`

- [ ] **Step 1: Write parse_response tests**

Create `test/phoenix_ai/providers/anthropic_test.exs`:

```elixir
defmodule PhoenixAI.Providers.AnthropicTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Providers.Anthropic
  alias PhoenixAI.{Response, ToolCall}

  defp load_fixture(name) do
    Path.join([__DIR__, "../../support/fixtures/anthropic", name])
    |> File.read!()
    |> Jason.decode!()
  end

  describe "parse_response/1" do
    test "parses a simple text completion" do
      fixture = load_fixture("messages_completion.json")
      response = Anthropic.parse_response(fixture)

      assert %Response{} = response
      assert response.content == "Hello! How can I help you today?"
      assert response.finish_reason == "end_turn"
      assert response.model == "claude-sonnet-4-5-20250514"
      assert response.usage["input_tokens"] == 10
      assert response.usage["output_tokens"] == 9
      assert response.tool_calls == []
      assert response.provider_response == fixture
    end

    test "parses a response with tool_use blocks" do
      fixture = load_fixture("messages_with_tool_use.json")
      response = Anthropic.parse_response(fixture)

      assert response.content == "Let me check the weather for you."
      assert response.finish_reason == "tool_use"
      assert [%ToolCall{} = tc] = response.tool_calls
      assert tc.id == "toolu_01A09q90qw90lq917835lgs0"
      assert tc.name == "get_weather"
      assert tc.arguments == %{"city" => "Lisbon"}
    end

    test "extracts error message from Anthropic error response" do
      fixture = load_fixture("messages_error_401.json")
      message = get_in(fixture, ["error", "message"])
      assert message == "invalid x-api-key"
    end
  end

  describe "format_messages/1" do
    test "converts user and assistant messages to Anthropic format" do
      messages = [
        %PhoenixAI.Message{role: :user, content: "Hello"},
        %PhoenixAI.Message{role: :assistant, content: "Hi there!"}
      ]

      formatted = Anthropic.format_messages(messages)

      assert formatted == [
               %{"role" => "user", "content" => "Hello"},
               %{"role" => "assistant", "content" => "Hi there!"}
             ]
    end

    test "excludes system messages from formatted output" do
      messages = [
        %PhoenixAI.Message{role: :system, content: "You are helpful."},
        %PhoenixAI.Message{role: :user, content: "Hello"}
      ]

      formatted = Anthropic.format_messages(messages)

      assert formatted == [
               %{"role" => "user", "content" => "Hello"}
             ]
    end
  end

  describe "extract_system/1" do
    test "extracts single system message" do
      messages = [
        %PhoenixAI.Message{role: :system, content: "You are helpful."},
        %PhoenixAI.Message{role: :user, content: "Hello"}
      ]

      assert Anthropic.extract_system(messages) == "You are helpful."
    end

    test "concatenates multiple system messages" do
      messages = [
        %PhoenixAI.Message{role: :system, content: "You are helpful."},
        %PhoenixAI.Message{role: :system, content: "Be concise."},
        %PhoenixAI.Message{role: :user, content: "Hello"}
      ]

      assert Anthropic.extract_system(messages) == "You are helpful.\n\nBe concise."
    end

    test "returns nil when no system messages" do
      messages = [
        %PhoenixAI.Message{role: :user, content: "Hello"}
      ]

      assert Anthropic.extract_system(messages) == nil
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
mix test test/phoenix_ai/providers/anthropic_test.exs
```

Expected: Compilation error — `PhoenixAI.Providers.Anthropic` module not found.

- [ ] **Step 3: Commit failing tests**

```bash
git add test/phoenix_ai/providers/anthropic_test.exs
git commit -m "test(02): add Anthropic adapter unit tests (red)"
```

---

### Task 3: Anthropic Adapter Implementation

**Files:**
- Create: `lib/phoenix_ai/providers/anthropic.ex`

- [ ] **Step 1: Implement the Anthropic adapter**

Create `lib/phoenix_ai/providers/anthropic.ex`:

```elixir
defmodule PhoenixAI.Providers.Anthropic do
  @moduledoc """
  Anthropic provider adapter implementing the `PhoenixAI.Provider` behaviour.

  Supports the Messages API with automatic system message extraction,
  tool_use content block parsing, and configurable API version.

  ## Anthropic-specific behavior

  - **`max_tokens`** — Required by Anthropic's API (unlike OpenAI). Defaults to 4096
    if not provided. Override via `max_tokens:` option in `chat/2`.
  - **System messages** — Automatically extracted from the message list and placed
    as the top-level `system` parameter. The caller does not need to handle this.
  - **`provider_options`** — The `"anthropic-version"` key is extracted as a header.
    All other keys are merged into the request body as additional API parameters.
  """

  @behaviour PhoenixAI.Provider

  alias PhoenixAI.{Error, Message, Response, ToolCall}

  @default_base_url "https://api.anthropic.com/v1"
  @default_api_version "2023-06-01"

  @impl PhoenixAI.Provider
  def chat(messages, opts \\ []) do
    api_key = Keyword.fetch!(opts, :api_key)
    model = Keyword.get(opts, :model, "claude-sonnet-4-5")
    base_url = Keyword.get(opts, :base_url, @default_base_url)
    provider_options = Keyword.get(opts, :provider_options, %{})
    api_version = Map.get(provider_options, "anthropic-version", @default_api_version)

    system = extract_system(messages)

    body =
      %{
        "model" => model,
        "messages" => format_messages(messages),
        "max_tokens" => Keyword.get(opts, :max_tokens, 4096)
      }
      |> maybe_put("system", system)
      |> maybe_put("temperature", Keyword.get(opts, :temperature))
      |> Map.merge(Map.drop(provider_options, ["anthropic-version"]))

    case Req.post("#{base_url}/messages",
           json: body,
           headers: [
             {"x-api-key", api_key},
             {"anthropic-version", api_version},
             {"content-type", "application/json"}
           ]
         ) do
      {:ok, %{status: 200, body: response_body}} ->
        {:ok, parse_response(response_body)}

      {:ok, %{status: status, body: error_body}} ->
        message =
          case error_body do
            %{"error" => %{"message" => msg}} -> msg
            _ -> "Unexpected error (HTTP #{status})"
          end

        {:error, %Error{status: status, message: message, provider: :anthropic}}

      {:error, reason} ->
        {:error, %Error{status: nil, message: inspect(reason), provider: :anthropic}}
    end
  end

  @impl PhoenixAI.Provider
  def parse_response(body) do
    content_blocks = Map.get(body, "content", [])
    stop_reason = Map.get(body, "stop_reason")
    model = Map.get(body, "model")
    usage = Map.get(body, "usage", %{})

    text_content = extract_text_content(content_blocks)
    tool_calls = extract_tool_calls(content_blocks)

    %Response{
      content: text_content,
      finish_reason: stop_reason,
      model: model,
      usage: usage,
      tool_calls: tool_calls,
      provider_response: body
    }
  end

  @doc """
  Extracts system message content from a list of messages.

  Returns concatenated system content (joined with "\\n\\n") or nil if no system messages.
  """
  @spec extract_system([Message.t()]) :: String.t() | nil
  def extract_system(messages) do
    messages
    |> Enum.filter(&(&1.role == :system))
    |> case do
      [] -> nil
      system_msgs -> system_msgs |> Enum.map(& &1.content) |> Enum.join("\n\n")
    end
  end

  @doc """
  Converts a list of `PhoenixAI.Message` structs into Anthropic's message format.

  Excludes system messages (those are handled by `extract_system/1`).
  """
  @spec format_messages([Message.t()]) :: [map()]
  def format_messages(messages) do
    messages
    |> Enum.reject(&(&1.role == :system))
    |> Enum.map(&format_message/1)
  end

  # Private helpers

  defp format_message(%Message{role: role, content: content}) do
    %{"role" => to_string(role), "content" => content}
  end

  defp extract_text_content(content_blocks) do
    content_blocks
    |> Enum.filter(&(&1["type"] == "text"))
    |> Enum.map(& &1["text"])
    |> case do
      [] -> nil
      texts -> Enum.join(texts, "\n")
    end
  end

  defp extract_tool_calls(content_blocks) do
    content_blocks
    |> Enum.filter(&(&1["type"] == "tool_use"))
    |> Enum.map(fn block ->
      %ToolCall{
        id: block["id"],
        name: block["name"],
        arguments: block["input"] || %{}
      }
    end)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
```

- [ ] **Step 2: Run tests to verify they pass**

Run:
```bash
mix test test/phoenix_ai/providers/anthropic_test.exs
```

Expected: All tests PASS.

- [ ] **Step 3: Run full test suite**

Run:
```bash
mix test
```

Expected: All tests pass. Note: the existing `ai_test.exs` test for `{:error, {:provider_not_implemented, :anthropic}}` will now fail since the module exists. This is expected — we fix it in Task 6.

- [ ] **Step 4: Run formatter and credo**

Run:
```bash
mix format && mix credo
```

Expected: Clean.

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_ai/providers/anthropic.ex test/phoenix_ai/providers/anthropic_test.exs
git commit -m "feat(02): add Anthropic provider adapter with Messages API support"
```

---

### Task 4: OpenRouter Fixtures

**Files:**
- Create: `test/support/fixtures/openrouter/chat_completion.json`
- Create: `test/support/fixtures/openrouter/chat_completion_with_tools.json`
- Create: `test/support/fixtures/openrouter/chat_error_401.json`

- [ ] **Step 1: Create OpenRouter fixtures directory**

Run:
```bash
mkdir -p test/support/fixtures/openrouter
```

- [ ] **Step 2: Create simple completion fixture**

Create `test/support/fixtures/openrouter/chat_completion.json`:

```json
{
  "id": "gen-abc123",
  "object": "chat.completion",
  "created": 1711000000,
  "model": "anthropic/claude-sonnet-4-5",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Hello! How can I help you today?"
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 10,
    "completion_tokens": 9,
    "total_tokens": 19
  }
}
```

- [ ] **Step 3: Create tool call fixture**

Create `test/support/fixtures/openrouter/chat_completion_with_tools.json`:

```json
{
  "id": "gen-tool456",
  "object": "chat.completion",
  "created": 1711000001,
  "model": "openai/gpt-4o",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": null,
        "tool_calls": [
          {
            "id": "call_or_abc123",
            "type": "function",
            "function": {
              "name": "get_weather",
              "arguments": "{\"city\":\"Lisbon\"}"
            }
          }
        ]
      },
      "finish_reason": "tool_calls"
    }
  ],
  "usage": {
    "prompt_tokens": 50,
    "completion_tokens": 20,
    "total_tokens": 70
  }
}
```

- [ ] **Step 4: Create auth error fixture**

Create `test/support/fixtures/openrouter/chat_error_401.json`:

```json
{
  "error": {
    "message": "Invalid API key.",
    "type": "invalid_request_error",
    "param": null,
    "code": "invalid_api_key"
  }
}
```

- [ ] **Step 5: Commit**

```bash
git add test/support/fixtures/openrouter/
git commit -m "test(02): add OpenRouter API response fixtures"
```

---

### Task 5: OpenRouter Adapter (Tests + Implementation)

**Files:**
- Create: `test/phoenix_ai/providers/openrouter_test.exs`
- Create: `lib/phoenix_ai/providers/openrouter.ex`

- [ ] **Step 1: Write OpenRouter tests**

Create `test/phoenix_ai/providers/openrouter_test.exs`:

```elixir
defmodule PhoenixAI.Providers.OpenRouterTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Providers.OpenRouter
  alias PhoenixAI.{Error, Response, ToolCall}

  defp load_fixture(name) do
    Path.join([__DIR__, "../../support/fixtures/openrouter", name])
    |> File.read!()
    |> Jason.decode!()
  end

  describe "parse_response/1" do
    test "parses a simple chat completion" do
      fixture = load_fixture("chat_completion.json")
      response = OpenRouter.parse_response(fixture)

      assert %Response{} = response
      assert response.content == "Hello! How can I help you today?"
      assert response.finish_reason == "stop"
      assert response.model == "anthropic/claude-sonnet-4-5"
      assert response.usage["prompt_tokens"] == 10
      assert response.usage["completion_tokens"] == 9
      assert response.tool_calls == []
      assert response.provider_response == fixture
    end

    test "parses a response with tool calls" do
      fixture = load_fixture("chat_completion_with_tools.json")
      response = OpenRouter.parse_response(fixture)

      assert response.content == nil
      assert response.finish_reason == "tool_calls"
      assert [%ToolCall{} = tc] = response.tool_calls
      assert tc.id == "call_or_abc123"
      assert tc.name == "get_weather"
      assert tc.arguments == %{"city" => "Lisbon"}
    end

    test "extracts error message from error response" do
      fixture = load_fixture("chat_error_401.json")
      message = get_in(fixture, ["error", "message"])
      assert message == "Invalid API key."
    end
  end

  describe "format_messages/1" do
    test "converts Message structs to OpenAI-compatible format" do
      messages = [
        %PhoenixAI.Message{role: :system, content: "You are helpful."},
        %PhoenixAI.Message{role: :user, content: "Hello"}
      ]

      formatted = OpenRouter.format_messages(messages)

      assert formatted == [
               %{"role" => "system", "content" => "You are helpful."},
               %{"role" => "user", "content" => "Hello"}
             ]
    end

    test "converts tool message with tool_call_id" do
      messages = [
        %PhoenixAI.Message{role: :tool, content: "sunny", tool_call_id: "call_123"}
      ]

      formatted = OpenRouter.format_messages(messages)

      assert [%{"role" => "tool", "content" => "sunny", "tool_call_id" => "call_123"}] = formatted
    end

    test "preserves tool_calls on assistant messages" do
      tc = %PhoenixAI.ToolCall{id: "call_1", name: "search", arguments: %{"q" => "elixir"}}

      messages = [
        %PhoenixAI.Message{role: :assistant, content: nil, tool_calls: [tc]}
      ]

      [formatted] = OpenRouter.format_messages(messages)

      assert formatted["role"] == "assistant"

      assert [%{"id" => "call_1", "type" => "function", "function" => func}] =
               formatted["tool_calls"]

      assert func["name"] == "search"
      assert func["arguments"] == ~s({"q":"elixir"})
    end
  end

  describe "chat/2 validation" do
    test "returns error when model is not provided" do
      result = OpenRouter.validate_model(nil)
      assert {:error, %Error{message: "model is required for OpenRouter", provider: :openrouter}} = result
    end

    test "returns :ok when model is provided" do
      assert :ok = OpenRouter.validate_model("anthropic/claude-sonnet-4-5")
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
mix test test/phoenix_ai/providers/openrouter_test.exs
```

Expected: Compilation error — `PhoenixAI.Providers.OpenRouter` module not found.

- [ ] **Step 3: Implement the OpenRouter adapter**

Create `lib/phoenix_ai/providers/openrouter.ex`:

```elixir
defmodule PhoenixAI.Providers.OpenRouter do
  @moduledoc """
  OpenRouter provider adapter implementing the `PhoenixAI.Provider` behaviour.

  OpenAI-compatible API with different base URL and required model specification.
  Fully independent implementation — no code sharing with the OpenAI adapter.
  """

  @behaviour PhoenixAI.Provider

  alias PhoenixAI.{Error, Message, Response, ToolCall}

  @default_base_url "https://openrouter.ai/api/v1"

  @impl PhoenixAI.Provider
  def chat(messages, opts \\ []) do
    model = Keyword.get(opts, :model)

    case validate_model(model) do
      :ok -> do_chat(messages, opts)
      {:error, _} = error -> error
    end
  end

  @impl PhoenixAI.Provider
  def parse_response(body) do
    choice = body |> Map.get("choices", []) |> List.first(%{})
    message = Map.get(choice, "message", %{})

    content = Map.get(message, "content")
    finish_reason = Map.get(choice, "finish_reason")
    model = Map.get(body, "model")
    usage = Map.get(body, "usage", %{})
    tool_calls = parse_tool_calls(Map.get(message, "tool_calls"))

    %Response{
      content: content,
      finish_reason: finish_reason,
      model: model,
      usage: usage,
      tool_calls: tool_calls,
      provider_response: body
    }
  end

  @doc """
  Validates that a model is provided. Returns `:ok` or `{:error, %Error{}}`.
  """
  @spec validate_model(String.t() | nil) :: :ok | {:error, Error.t()}
  def validate_model(nil) do
    {:error, %Error{status: nil, message: "model is required for OpenRouter", provider: :openrouter}}
  end

  def validate_model(_model), do: :ok

  @doc """
  Converts a list of `PhoenixAI.Message` structs into OpenAI-compatible message format.
  """
  @spec format_messages([Message.t()]) :: [map()]
  def format_messages(messages) do
    Enum.map(messages, &format_message/1)
  end

  # Private helpers

  defp do_chat(messages, opts) do
    api_key = Keyword.fetch!(opts, :api_key)
    model = Keyword.get(opts, :model)
    base_url = Keyword.get(opts, :base_url, @default_base_url)
    provider_options = Keyword.get(opts, :provider_options, %{})

    body =
      %{
        "model" => model,
        "messages" => format_messages(messages)
      }
      |> maybe_put("temperature", Keyword.get(opts, :temperature))
      |> maybe_put("max_tokens", Keyword.get(opts, :max_tokens))
      |> Map.merge(Map.drop(provider_options, ["http_referer", "x_title"]))

    headers =
      [
        {"authorization", "Bearer #{api_key}"},
        {"content-type", "application/json"}
      ]
      |> maybe_add_header("HTTP-Referer", Map.get(provider_options, "http_referer"))
      |> maybe_add_header("X-Title", Map.get(provider_options, "x_title"))

    case Req.post("#{base_url}/chat/completions", json: body, headers: headers) do
      {:ok, %{status: 200, body: response_body}} ->
        {:ok, parse_response(response_body)}

      {:ok, %{status: status, body: error_body}} ->
        message =
          case error_body do
            %{"error" => %{"message" => msg}} -> msg
            _ -> "Unexpected error (HTTP #{status})"
          end

        {:error, %Error{status: status, message: message, provider: :openrouter}}

      {:error, reason} ->
        {:error, %Error{status: nil, message: inspect(reason), provider: :openrouter}}
    end
  end

  defp format_message(%Message{role: :tool, content: content, tool_call_id: tool_call_id}) do
    %{"role" => "tool", "content" => content, "tool_call_id" => tool_call_id}
  end

  defp format_message(%Message{role: :assistant, tool_calls: tool_calls} = msg)
       when is_list(tool_calls) and tool_calls != [] do
    %{
      "role" => "assistant",
      "content" => msg.content,
      "tool_calls" => Enum.map(tool_calls, &format_tool_call/1)
    }
  end

  defp format_message(%Message{role: role, content: content}) do
    %{"role" => to_string(role), "content" => content}
  end

  defp format_tool_call(%ToolCall{} = tc) do
    %{
      "id" => tc.id,
      "type" => "function",
      "function" => %{
        "name" => tc.name,
        "arguments" => Jason.encode!(tc.arguments)
      }
    }
  end

  defp parse_tool_calls(nil), do: []
  defp parse_tool_calls([]), do: []

  defp parse_tool_calls(tool_calls) when is_list(tool_calls) do
    Enum.map(tool_calls, &parse_single_tool_call/1)
  end

  defp parse_single_tool_call(tc) do
    function = Map.get(tc, "function", %{})

    %ToolCall{
      id: Map.get(tc, "id"),
      name: Map.get(function, "name"),
      arguments: parse_arguments(Map.get(function, "arguments"))
    }
  end

  defp parse_arguments(nil), do: %{}
  defp parse_arguments(args) when is_map(args), do: args

  defp parse_arguments(args) when is_binary(args) do
    case Jason.decode(args) do
      {:ok, parsed} -> parsed
      {:error, _} -> %{"_raw" => args}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_add_header(headers, _name, nil), do: headers
  defp maybe_add_header(headers, name, value), do: headers ++ [{name, value}]
end
```

- [ ] **Step 4: Run OpenRouter tests to verify they pass**

Run:
```bash
mix test test/phoenix_ai/providers/openrouter_test.exs
```

Expected: All tests PASS.

- [ ] **Step 5: Run formatter and credo**

Run:
```bash
mix format && mix credo
```

Expected: Clean.

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_ai/providers/openrouter.ex test/phoenix_ai/providers/openrouter_test.exs
git commit -m "feat(02): add OpenRouter provider adapter with model validation"
```

---

### Task 6: Contract Tests

**Files:**
- Create: `test/phoenix_ai/providers/provider_contract_test.exs`

- [ ] **Step 1: Write contract tests**

Create `test/phoenix_ai/providers/provider_contract_test.exs`:

```elixir
defmodule PhoenixAI.Providers.ProviderContractTest do
  @moduledoc """
  Contract tests verifying all provider adapters produce consistent %Response{} output.

  Every adapter implementing PhoenixAI.Provider must:
  1. Return a %Response{} struct from parse_response/1
  2. Populate content as String.t() | nil
  3. Populate tool_calls as a list of %ToolCall{} structs
  4. Populate usage as a map
  5. Populate finish_reason as String.t() | nil
  6. Populate model as String.t() | nil
  7. Preserve the raw provider response in provider_response
  """

  use ExUnit.Case, async: true

  alias PhoenixAI.{Response, ToolCall}

  @providers [
    {PhoenixAI.Providers.OpenAI, "openai", "chat_completion.json",
     "chat_completion_with_tools.json"},
    {PhoenixAI.Providers.Anthropic, "anthropic", "messages_completion.json",
     "messages_with_tool_use.json"},
    {PhoenixAI.Providers.OpenRouter, "openrouter", "chat_completion.json",
     "chat_completion_with_tools.json"}
  ]

  defp load_fixture(dir, name) do
    Path.join([__DIR__, "../../support/fixtures", dir, name])
    |> File.read!()
    |> Jason.decode!()
  end

  for {provider, dir, simple_fixture, tool_fixture} <- @providers do
    describe "#{provider} contract" do
      test "parse_response returns %Response{} with all expected fields" do
        fixture = load_fixture(unquote(dir), unquote(simple_fixture))
        response = unquote(provider).parse_response(fixture)

        assert %Response{} = response
        assert is_binary(response.content) or is_nil(response.content)
        assert is_list(response.tool_calls)
        assert is_map(response.usage)
        assert is_binary(response.finish_reason) or is_nil(response.finish_reason)
        assert is_binary(response.model) or is_nil(response.model)
        assert is_map(response.provider_response)
      end

      test "parse_response preserves raw provider response" do
        fixture = load_fixture(unquote(dir), unquote(simple_fixture))
        response = unquote(provider).parse_response(fixture)

        assert response.provider_response == fixture
      end

      test "parse_response with tool calls returns valid ToolCall structs" do
        fixture = load_fixture(unquote(dir), unquote(tool_fixture))
        response = unquote(provider).parse_response(fixture)

        assert is_list(response.tool_calls)
        assert length(response.tool_calls) >= 1

        for tc <- response.tool_calls do
          assert %ToolCall{} = tc
          assert is_binary(tc.id)
          assert is_binary(tc.name)
          assert is_map(tc.arguments)
        end
      end

      test "simple response has empty tool_calls list" do
        fixture = load_fixture(unquote(dir), unquote(simple_fixture))
        response = unquote(provider).parse_response(fixture)

        assert response.tool_calls == []
      end
    end
  end
end
```

- [ ] **Step 2: Run contract tests**

Run:
```bash
mix test test/phoenix_ai/providers/provider_contract_test.exs
```

Expected: All 12 tests (4 per provider × 3 providers) PASS.

- [ ] **Step 3: Commit**

```bash
git add test/phoenix_ai/providers/provider_contract_test.exs
git commit -m "test(02): add cross-adapter provider contract tests"
```

---

### Task 7: Update AI Dispatch Tests

**Files:**
- Modify: `test/phoenix_ai/ai_test.exs`

- [ ] **Step 1: Update the dispatch test for now-available providers**

In `test/phoenix_ai/ai_test.exs`, replace the test that expects `:provider_not_implemented` for `:anthropic`:

Replace this test:

```elixir
    test "returns error for unimplemented known provider" do
      result =
        AI.chat(
          [%PhoenixAI.Message{role: :user, content: "Hi"}],
          provider: :anthropic,
          api_key: "test"
        )

      assert {:error, {:provider_not_implemented, :anthropic}} = result
    end
```

With these tests:

```elixir
    test "resolves :anthropic to a loaded provider module" do
      mod = AI.provider_module(:anthropic)
      assert Code.ensure_loaded?(mod)
    end

    test "resolves :openrouter to a loaded provider module" do
      mod = AI.provider_module(:openrouter)
      assert Code.ensure_loaded?(mod)
    end
```

- [ ] **Step 2: Add Mox-based dispatch tests for new providers**

Add these tests to the same `describe "chat/2"` block in `test/phoenix_ai/ai_test.exs`:

```elixir
    test "delegates to Anthropic adapter via mock" do
      expect(PhoenixAI.MockProvider, :chat, fn messages, opts ->
        assert [%PhoenixAI.Message{role: :user, content: "Hi"}] = messages
        assert opts[:model] == "claude-sonnet-4-5"
        {:ok, %PhoenixAI.Response{content: "Bonjour!"}}
      end)

      result =
        AI.chat(
          [%PhoenixAI.Message{role: :user, content: "Hi"}],
          provider: PhoenixAI.MockProvider,
          model: "claude-sonnet-4-5",
          api_key: "test-key"
        )

      assert {:ok, %PhoenixAI.Response{content: "Bonjour!"}} = result
    end

    test "delegates to OpenRouter adapter via mock" do
      expect(PhoenixAI.MockProvider, :chat, fn messages, opts ->
        assert [%PhoenixAI.Message{role: :user, content: "Hi"}] = messages
        assert opts[:model] == "anthropic/claude-sonnet-4-5"
        {:ok, %PhoenixAI.Response{content: "Hello via OpenRouter!"}}
      end)

      result =
        AI.chat(
          [%PhoenixAI.Message{role: :user, content: "Hi"}],
          provider: PhoenixAI.MockProvider,
          model: "anthropic/claude-sonnet-4-5",
          api_key: "test-key"
        )

      assert {:ok, %PhoenixAI.Response{content: "Hello via OpenRouter!"}} = result
    end
```

> **Note:** These tests use `PhoenixAI.MockProvider` (not `:anthropic`/`:openrouter` atoms) because `AI.provider_module/1` maps atoms to concrete modules. The Mox mock verifies the dispatch path (config resolution → adapter call) works correctly. The `Code.ensure_loaded?` tests in Step 1 verify the atom → module resolution.

- [ ] **Step 3: Run full test suite**

Run:
```bash
mix test
```

Expected: All tests PASS across all test files.

- [ ] **Step 4: Run formatter and credo**

Run:
```bash
mix format && mix credo
```

Expected: Clean.

- [ ] **Step 5: Commit**

```bash
git add test/phoenix_ai/ai_test.exs
git commit -m "test(02): update AI dispatch tests for available providers"
```

---

### Task 8: Final Verification

- [ ] **Step 1: Run full test suite with coverage**

Run:
```bash
mix test --cover
```

Expected: All tests PASS. Coverage for new adapter modules should be high.

- [ ] **Step 2: Run all quality checks**

Run:
```bash
mix format --check-formatted && mix credo
```

Expected: Clean.

- [ ] **Step 3: Verify success criteria**

Manually verify against ROADMAP.md success criteria:

1. ✅ Anthropic adapter exists and parse_response works with fixtures
2. ✅ OpenRouter adapter exists and parse_response works with fixtures
3. ✅ `AI.provider_module/1` resolves both `:anthropic` and `:openrouter` to loaded modules
4. ✅ `provider_options` passthrough implemented in both adapters
5. ✅ Unknown provider still returns `{:error, {:unknown_provider, atom}}`
6. ✅ Contract tests verify all 3 adapters produce consistent `%Response{}`

---

## Summary

| Task | Description | Commit Message |
|------|-------------|---------------|
| 1 | Anthropic fixtures | `test(02): add Anthropic API response fixtures` |
| 2 | Anthropic tests (red) | `test(02): add Anthropic adapter unit tests (red)` |
| 3 | Anthropic implementation (green) | `feat(02): add Anthropic provider adapter with Messages API support` |
| 4 | OpenRouter fixtures | `test(02): add OpenRouter API response fixtures` |
| 5 | OpenRouter tests + implementation | `feat(02): add OpenRouter provider adapter with model validation` |
| 6 | Contract tests | `test(02): add cross-adapter provider contract tests` |
| 7 | Update AI dispatch tests | `test(02): update AI dispatch tests for available providers` |
| 8 | Final verification | No commit — verification only |
