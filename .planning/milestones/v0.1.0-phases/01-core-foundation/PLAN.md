# Phase 1: Core Foundation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish the library skeleton with data model structs, Provider behaviour, config resolution, OpenAI adapter, and supervision child_spec.

**Architecture:** Thin AI Facade — `AI` module resolves provider atoms to modules, merges config (call-site > config.exs > env vars > defaults), delegates to `provider.chat/2`. Each provider adapter owns its HTTP.

**Tech Stack:** Elixir ~> 1.18, Req ~> 0.5, Jason ~> 1.4, NimbleOptions ~> 1.1, Telemetry ~> 1.3, Finch ~> 0.19, Mox ~> 1.2

---

## File Map

| File | Responsibility |
|------|---------------|
| `mix.exs` | Project definition, deps, Elixir version |
| `.formatter.exs` | Code formatter config |
| `.credo.exs` | Credo linting rules |
| `.github/workflows/ci.yml` | GitHub Actions CI pipeline |
| `lib/ai.ex` | Thin public facade: `AI.chat/2` |
| `lib/phoenix_ai/phoenix_ai.ex` | Top-level module, `child_spec/1` |
| `lib/phoenix_ai/provider.ex` | `@behaviour PhoenixAI.Provider` |
| `lib/phoenix_ai/config.ex` | Config cascade resolution |
| `lib/phoenix_ai/error.ex` | `%PhoenixAI.Error{}` struct |
| `lib/phoenix_ai/message.ex` | `%PhoenixAI.Message{}` struct |
| `lib/phoenix_ai/response.ex` | `%PhoenixAI.Response{}` struct |
| `lib/phoenix_ai/tool_call.ex` | `%PhoenixAI.ToolCall{}` struct |
| `lib/phoenix_ai/tool_result.ex` | `%PhoenixAI.ToolResult{}` struct |
| `lib/phoenix_ai/conversation.ex` | `%PhoenixAI.Conversation{}` stub |
| `lib/phoenix_ai/stream_chunk.ex` | `%PhoenixAI.StreamChunk{}` stub |
| `lib/phoenix_ai/providers/openai.ex` | OpenAI adapter |
| `test/test_helper.exs` | ExUnit + Mox setup |
| `test/phoenix_ai/message_test.exs` | Message struct tests |
| `test/phoenix_ai/response_test.exs` | Response struct tests |
| `test/phoenix_ai/config_test.exs` | Config resolution tests |
| `test/phoenix_ai/ai_test.exs` | AI facade tests (Mox) |
| `test/phoenix_ai/providers/openai_test.exs` | OpenAI adapter tests (fixtures) |
| `test/support/fixtures/openai/chat_completion.json` | Recorded OpenAI response |
| `test/support/fixtures/openai/chat_completion_with_tools.json` | Response with tool calls |
| `test/support/fixtures/openai/chat_error_401.json` | Recorded error response |
| `config/config.exs` | Base config |

---

### Task 1: Mix Project Scaffold

**Files:**
- Create: `mix.exs`
- Create: `.formatter.exs`
- Create: `config/config.exs`
- Create: `.gitignore`

- [ ] **Step 1: Create the Mix project**

Run: `mix new phoenix_ai --module PhoenixAI`

Expected: Project scaffolded with `mix.exs`, `lib/phoenix_ai.ex`, `test/` directory.

- [ ] **Step 2: Update mix.exs with dependencies and project config**

Replace the contents of `mix.exs`:

```elixir
defmodule PhoenixAI.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/franciscpd/phoenix-ai"

  def project do
    [
      app: :phoenix_ai,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test
      ],
      # Hex
      description: "AI integration library for Elixir inspired by laravel/ai",
      package: package(),
      # Docs
      name: "PhoenixAI",
      source_url: @source_url,
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:nimble_options, "~> 1.1"},
      {:telemetry, "~> 1.3"},
      {:finch, "~> 0.19"},

      # Dev/test
      {:mox, "~> 1.2", only: :test},
      {:excoveralls, "~> 0.18", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"]
    ]
  end
end
```

- [ ] **Step 3: Update .formatter.exs**

```elixir
[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]
```

- [ ] **Step 4: Create config/config.exs**

```elixir
import Config
```

- [ ] **Step 5: Update .gitignore**

Ensure `.gitignore` includes:

```
/_build/
/cover/
/deps/
/doc/
/.fetch
erl_crash.dump
*.ez
phoenix_ai-*.tar
/tmp/
```

- [ ] **Step 6: Fetch dependencies and verify compilation**

Run: `mix deps.get && mix compile`

Expected: All dependencies fetched, project compiles with 0 errors.

- [ ] **Step 7: Commit**

```bash
git add mix.exs mix.lock .formatter.exs .gitignore config/ lib/ test/
git commit -m "chore: scaffold mix project with dependencies"
```

---

### Task 2: Data Model Structs

**Files:**
- Create: `lib/phoenix_ai/message.ex`
- Create: `lib/phoenix_ai/response.ex`
- Create: `lib/phoenix_ai/tool_call.ex`
- Create: `lib/phoenix_ai/tool_result.ex`
- Create: `lib/phoenix_ai/error.ex`
- Create: `lib/phoenix_ai/conversation.ex`
- Create: `lib/phoenix_ai/stream_chunk.ex`
- Create: `test/phoenix_ai/message_test.exs`
- Create: `test/phoenix_ai/response_test.exs`

- [ ] **Step 1: Write failing test for Message struct**

Create `test/phoenix_ai/message_test.exs`:

```elixir
defmodule PhoenixAI.MessageTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Message

  describe "struct" do
    test "creates a user message with content" do
      msg = %Message{role: :user, content: "Hello"}
      assert msg.role == :user
      assert msg.content == "Hello"
      assert msg.metadata == %{}
      assert msg.tool_calls == nil
      assert msg.tool_call_id == nil
    end

    test "creates a system message" do
      msg = %Message{role: :system, content: "You are helpful."}
      assert msg.role == :system
      assert msg.content == "You are helpful."
    end

    test "creates a tool message with tool_call_id" do
      msg = %Message{role: :tool, content: "result", tool_call_id: "call_123"}
      assert msg.role == :tool
      assert msg.tool_call_id == "call_123"
    end

    test "creates an assistant message with tool_calls" do
      tool_call = %PhoenixAI.ToolCall{id: "call_1", name: "search", arguments: %{"q" => "elixir"}}
      msg = %Message{role: :assistant, tool_calls: [tool_call]}
      assert msg.role == :assistant
      assert [%PhoenixAI.ToolCall{name: "search"}] = msg.tool_calls
    end

    test "metadata defaults to empty map" do
      msg = %Message{role: :user, content: "test"}
      assert msg.metadata == %{}
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/phoenix_ai/message_test.exs`

Expected: FAIL — `PhoenixAI.Message.__struct__/0 is undefined`

- [ ] **Step 3: Implement ToolCall struct**

Create `lib/phoenix_ai/tool_call.ex`:

```elixir
defmodule PhoenixAI.ToolCall do
  @moduledoc "Represents an AI model's intent to invoke a tool."

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t() | nil,
          arguments: map()
        }

  defstruct [:id, :name, arguments: %{}]
end
```

- [ ] **Step 4: Implement Message struct**

Create `lib/phoenix_ai/message.ex`:

```elixir
defmodule PhoenixAI.Message do
  @moduledoc "A single turn in a conversation with an AI model."

  @type role :: :system | :user | :assistant | :tool

  @type t :: %__MODULE__{
          role: role(),
          content: String.t() | nil,
          tool_call_id: String.t() | nil,
          tool_calls: [PhoenixAI.ToolCall.t()] | nil,
          metadata: map()
        }

  defstruct [:role, :content, :tool_call_id, :tool_calls, metadata: %{}]
end
```

- [ ] **Step 5: Run Message test to verify it passes**

Run: `mix test test/phoenix_ai/message_test.exs`

Expected: All 5 tests PASS.

- [ ] **Step 6: Write failing test for Response struct**

Create `test/phoenix_ai/response_test.exs`:

```elixir
defmodule PhoenixAI.ResponseTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Response

  describe "struct" do
    test "creates a response with content" do
      resp = %Response{content: "Hello!", finish_reason: "stop", model: "gpt-4o"}
      assert resp.content == "Hello!"
      assert resp.finish_reason == "stop"
      assert resp.model == "gpt-4o"
      assert resp.tool_calls == []
      assert resp.usage == %{}
      assert resp.provider_response == %{}
    end

    test "creates a response with tool calls" do
      tc = %PhoenixAI.ToolCall{id: "call_1", name: "search"}
      resp = %Response{tool_calls: [tc], finish_reason: "tool_calls"}
      assert [%PhoenixAI.ToolCall{name: "search"}] = resp.tool_calls
    end

    test "preserves raw provider response" do
      raw = %{"id" => "chatcmpl-123", "object" => "chat.completion"}
      resp = %Response{content: "Hi", provider_response: raw}
      assert resp.provider_response["id"] == "chatcmpl-123"
    end
  end
end
```

- [ ] **Step 7: Implement Response struct**

Create `lib/phoenix_ai/response.ex`:

```elixir
defmodule PhoenixAI.Response do
  @moduledoc "Canonical response from an AI provider."

  @type t :: %__MODULE__{
          content: String.t() | nil,
          tool_calls: [PhoenixAI.ToolCall.t()],
          usage: map(),
          finish_reason: String.t() | nil,
          model: String.t() | nil,
          provider_response: map()
        }

  defstruct [:content, :finish_reason, :model, tool_calls: [], usage: %{}, provider_response: %{}]
end
```

- [ ] **Step 8: Run Response test to verify it passes**

Run: `mix test test/phoenix_ai/response_test.exs`

Expected: All 3 tests PASS.

- [ ] **Step 9: Implement remaining structs (ToolResult, Error, Conversation, StreamChunk)**

Create `lib/phoenix_ai/tool_result.ex`:

```elixir
defmodule PhoenixAI.ToolResult do
  @moduledoc "Output of executing a tool."

  @type t :: %__MODULE__{
          tool_call_id: String.t() | nil,
          content: String.t() | nil,
          error: String.t() | nil
        }

  defstruct [:tool_call_id, :content, :error]
end
```

Create `lib/phoenix_ai/error.ex`:

```elixir
defmodule PhoenixAI.Error do
  @moduledoc "Normalized error from an AI provider."

  @type t :: %__MODULE__{
          status: integer() | nil,
          message: String.t() | nil,
          provider: atom() | nil
        }

  defstruct [:status, :message, :provider]
end
```

Create `lib/phoenix_ai/conversation.ex`:

```elixir
defmodule PhoenixAI.Conversation do
  @moduledoc "An ordered list of messages with context. Used from Phase 4."

  @type t :: %__MODULE__{
          id: String.t() | nil,
          messages: [PhoenixAI.Message.t()],
          metadata: map()
        }

  defstruct [:id, messages: [], metadata: %{}]
end
```

Create `lib/phoenix_ai/stream_chunk.ex`:

```elixir
defmodule PhoenixAI.StreamChunk do
  @moduledoc "A single SSE event from a streaming response. Used from Phase 6."

  @type t :: %__MODULE__{
          delta: String.t() | nil,
          tool_call_delta: map() | nil,
          finish_reason: String.t() | nil
        }

  defstruct [:delta, :tool_call_delta, :finish_reason]
end
```

- [ ] **Step 10: Run all tests**

Run: `mix test`

Expected: All 8 tests PASS.

- [ ] **Step 11: Commit**

```bash
git add lib/phoenix_ai/message.ex lib/phoenix_ai/response.ex lib/phoenix_ai/tool_call.ex \
  lib/phoenix_ai/tool_result.ex lib/phoenix_ai/error.ex lib/phoenix_ai/conversation.ex \
  lib/phoenix_ai/stream_chunk.ex test/phoenix_ai/message_test.exs test/phoenix_ai/response_test.exs
git commit -m "feat: add canonical data model structs"
```

---

### Task 3: Provider Behaviour

**Files:**
- Create: `lib/phoenix_ai/provider.ex`

- [ ] **Step 1: Create Provider behaviour module**

Create `lib/phoenix_ai/provider.ex`:

```elixir
defmodule PhoenixAI.Provider do
  @moduledoc """
  Behaviour that all AI provider adapters must implement.

  Required callbacks:
  - `chat/2` — send messages, receive a complete response
  - `parse_response/1` — parse raw HTTP response body into canonical Response struct

  Optional callbacks:
  - `stream/3` — stream messages with chunks delivered via callback
  - `format_tools/1` — convert Tool modules to provider-specific JSON schema format
  - `parse_chunk/1` — parse a single SSE chunk into a StreamChunk struct
  """

  @callback chat(messages :: [PhoenixAI.Message.t()], opts :: keyword()) ::
              {:ok, PhoenixAI.Response.t()} | {:error, term()}

  @callback parse_response(body :: map()) :: PhoenixAI.Response.t()

  @callback stream(
              messages :: [PhoenixAI.Message.t()],
              callback :: (PhoenixAI.StreamChunk.t() -> any()),
              opts :: keyword()
            ) :: {:ok, PhoenixAI.Response.t()} | {:error, term()}

  @callback format_tools(tools :: [module()]) :: [map()]

  @callback parse_chunk(data :: String.t()) :: PhoenixAI.StreamChunk.t()

  @optional_callbacks [stream: 3, format_tools: 1, parse_chunk: 1]
end
```

- [ ] **Step 2: Verify compilation**

Run: `mix compile`

Expected: Compiles with 0 errors.

- [ ] **Step 3: Commit**

```bash
git add lib/phoenix_ai/provider.ex
git commit -m "feat: add Provider behaviour contract"
```

---

### Task 4: Config Resolution

**Files:**
- Create: `lib/phoenix_ai/config.ex`
- Create: `test/phoenix_ai/config_test.exs`

- [ ] **Step 1: Write failing test for config resolution**

Create `test/phoenix_ai/config_test.exs`:

```elixir
defmodule PhoenixAI.ConfigTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Config

  describe "resolve/2" do
    test "call-site opts take precedence over everything" do
      opts = Config.resolve(:openai, api_key: "call-site-key", model: "gpt-4o-mini")
      assert opts[:api_key] == "call-site-key"
      assert opts[:model] == "gpt-4o-mini"
    end

    test "falls back to application config" do
      Application.put_env(:phoenix_ai, :openai, api_key: "config-key")

      opts = Config.resolve(:openai, [])
      assert opts[:api_key] == "config-key"
    after
      Application.delete_env(:phoenix_ai, :openai)
    end

    test "falls back to env var when no config" do
      System.put_env("OPENAI_API_KEY", "env-key")

      opts = Config.resolve(:openai, [])
      assert opts[:api_key] == "env-key"
    after
      System.delete_env("OPENAI_API_KEY")
    end

    test "applies default model for openai" do
      opts = Config.resolve(:openai, api_key: "test")
      assert opts[:model] == "gpt-4o"
    end

    test "applies default model for anthropic without date suffix" do
      opts = Config.resolve(:anthropic, api_key: "test")
      assert opts[:model] == "claude-sonnet-4-5"
    end

    test "no default model for openrouter" do
      opts = Config.resolve(:openrouter, api_key: "test")
      assert opts[:model] == nil
    end

    test "call-site model overrides default" do
      opts = Config.resolve(:openai, api_key: "test", model: "gpt-3.5-turbo")
      assert opts[:model] == "gpt-3.5-turbo"
    end

    test "cascade order: call-site > config > env > defaults" do
      System.put_env("OPENAI_API_KEY", "env-key")
      Application.put_env(:phoenix_ai, :openai, api_key: "config-key", model: "config-model")

      opts = Config.resolve(:openai, model: "call-site-model")
      # api_key: config wins over env (call-site not provided)
      assert opts[:api_key] == "config-key"
      # model: call-site wins over config
      assert opts[:model] == "call-site-model"
    after
      System.delete_env("OPENAI_API_KEY")
      Application.delete_env(:phoenix_ai, :openai)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/phoenix_ai/config_test.exs`

Expected: FAIL — `PhoenixAI.Config.resolve/2 is undefined`

- [ ] **Step 3: Implement Config module**

Create `lib/phoenix_ai/config.ex`:

```elixir
defmodule PhoenixAI.Config do
  @moduledoc "Resolves configuration with cascade: call-site > config.exs > env vars > defaults."

  @env_vars %{
    openai: "OPENAI_API_KEY",
    anthropic: "ANTHROPIC_API_KEY",
    openrouter: "OPENROUTER_API_KEY"
  }

  @default_models %{
    openai: "gpt-4o",
    anthropic: "claude-sonnet-4-5"
  }

  @doc """
  Resolve configuration for a provider.

  Cascade order:
  1. Call-site opts (highest priority)
  2. Application config (`config :phoenix_ai, :provider_atom`)
  3. System env var fallback
  4. Provider defaults (lowest priority)
  """
  @spec resolve(atom(), keyword()) :: keyword()
  def resolve(provider, call_site_opts) do
    app_config = Application.get_env(:phoenix_ai, provider, [])
    env_opts = env_opts(provider)
    defaults = default_opts(provider)

    defaults
    |> Keyword.merge(env_opts)
    |> Keyword.merge(app_config)
    |> Keyword.merge(call_site_opts)
  end

  defp env_opts(provider) do
    case Map.get(@env_vars, provider) do
      nil -> []
      env_var ->
        case System.get_env(env_var) do
          nil -> []
          key -> [api_key: key]
        end
    end
  end

  defp default_opts(provider) do
    case Map.get(@default_models, provider) do
      nil -> []
      model -> [model: model]
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/phoenix_ai/config_test.exs`

Expected: All 8 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_ai/config.ex test/phoenix_ai/config_test.exs
git commit -m "feat: add config resolution with cascade"
```

---

### Task 5: OpenAI Adapter

**Files:**
- Create: `lib/phoenix_ai/providers/openai.ex`
- Create: `test/phoenix_ai/providers/openai_test.exs`
- Create: `test/support/fixtures/openai/chat_completion.json`
- Create: `test/support/fixtures/openai/chat_completion_with_tools.json`
- Create: `test/support/fixtures/openai/chat_error_401.json`

- [ ] **Step 1: Create fixture files**

Create `test/support/fixtures/openai/chat_completion.json`:

```json
{
  "id": "chatcmpl-abc123",
  "object": "chat.completion",
  "created": 1711000000,
  "model": "gpt-4o-2024-08-06",
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

Create `test/support/fixtures/openai/chat_completion_with_tools.json`:

```json
{
  "id": "chatcmpl-tool456",
  "object": "chat.completion",
  "created": 1711000001,
  "model": "gpt-4o-2024-08-06",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": null,
        "tool_calls": [
          {
            "id": "call_abc123",
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

Create `test/support/fixtures/openai/chat_error_401.json`:

```json
{
  "error": {
    "message": "Incorrect API key provided: sk-xxxx. You can find your API key at https://platform.openai.com/account/api-keys.",
    "type": "invalid_request_error",
    "param": null,
    "code": "invalid_api_key"
  }
}
```

- [ ] **Step 2: Write failing tests for OpenAI adapter**

Create `test/phoenix_ai/providers/openai_test.exs`:

```elixir
defmodule PhoenixAI.Providers.OpenAITest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Providers.OpenAI
  alias PhoenixAI.{Response, ToolCall}

  defp load_fixture(name) do
    Path.join([__DIR__, "../../support/fixtures/openai", name])
    |> File.read!()
    |> Jason.decode!()
  end

  describe "parse_response/1" do
    test "parses a simple chat completion" do
      fixture = load_fixture("chat_completion.json")
      response = OpenAI.parse_response(fixture)

      assert %Response{} = response
      assert response.content == "Hello! How can I help you today?"
      assert response.finish_reason == "stop"
      assert response.model == "gpt-4o-2024-08-06"
      assert response.usage["prompt_tokens"] == 10
      assert response.usage["completion_tokens"] == 9
      assert response.tool_calls == []
      assert response.provider_response == fixture
    end

    test "parses a response with tool calls" do
      fixture = load_fixture("chat_completion_with_tools.json")
      response = OpenAI.parse_response(fixture)

      assert response.content == nil
      assert response.finish_reason == "tool_calls"
      assert [%ToolCall{} = tc] = response.tool_calls
      assert tc.id == "call_abc123"
      assert tc.name == "get_weather"
      assert tc.arguments == %{"city" => "Lisbon"}
    end
  end

  describe "format_messages/1" do
    test "converts Message structs to OpenAI format" do
      messages = [
        %PhoenixAI.Message{role: :system, content: "You are helpful."},
        %PhoenixAI.Message{role: :user, content: "Hello"}
      ]

      formatted = OpenAI.format_messages(messages)

      assert formatted == [
               %{"role" => "system", "content" => "You are helpful."},
               %{"role" => "user", "content" => "Hello"}
             ]
    end

    test "converts tool message with tool_call_id" do
      messages = [
        %PhoenixAI.Message{role: :tool, content: "sunny", tool_call_id: "call_123"}
      ]

      formatted = OpenAI.format_messages(messages)

      assert [%{"role" => "tool", "content" => "sunny", "tool_call_id" => "call_123"}] = formatted
    end
  end
end
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `mix test test/phoenix_ai/providers/openai_test.exs`

Expected: FAIL — `PhoenixAI.Providers.OpenAI` module not found.

- [ ] **Step 4: Implement OpenAI adapter**

Create `lib/phoenix_ai/providers/openai.ex`:

```elixir
defmodule PhoenixAI.Providers.OpenAI do
  @moduledoc "OpenAI provider adapter. Implements `PhoenixAI.Provider`."

  @behaviour PhoenixAI.Provider

  @base_url "https://api.openai.com/v1"

  @impl true
  def chat(messages, opts) do
    url = "#{base_url(opts)}/chat/completions"

    body =
      %{
        model: opts[:model] || "gpt-4o",
        messages: format_messages(messages)
      }
      |> maybe_add(:temperature, opts[:temperature])
      |> maybe_add(:max_tokens, opts[:max_tokens])
      |> merge_provider_options(opts[:provider_options])

    headers = [
      {"authorization", "Bearer #{opts[:api_key]}"},
      {"content-type", "application/json"}
    ]

    case Req.post(url, json: body, headers: headers) do
      {:ok, %{status: 200, body: resp_body}} ->
        {:ok, parse_response(resp_body)}

      {:ok, %{status: status, body: resp_body}} ->
        {:error,
         %PhoenixAI.Error{
           status: status,
           message: extract_error(resp_body),
           provider: :openai
         }}

      {:error, reason} ->
        {:error,
         %PhoenixAI.Error{
           message: inspect(reason),
           provider: :openai
         }}
    end
  end

  @impl true
  def parse_response(%{"choices" => [choice | _]} = body) do
    message = choice["message"] || %{}

    %PhoenixAI.Response{
      content: message["content"],
      tool_calls: parse_tool_calls(message),
      finish_reason: choice["finish_reason"],
      model: body["model"],
      usage: body["usage"] || %{},
      provider_response: body
    }
  end

  @doc "Convert PhoenixAI.Message structs to OpenAI's message format."
  def format_messages(messages) do
    Enum.map(messages, &format_message/1)
  end

  defp format_message(%PhoenixAI.Message{role: :tool} = msg) do
    %{"role" => "tool", "content" => msg.content, "tool_call_id" => msg.tool_call_id}
  end

  defp format_message(%PhoenixAI.Message{} = msg) do
    base = %{"role" => to_string(msg.role), "content" => msg.content}

    case msg.tool_calls do
      nil -> base
      [] -> base
      tool_calls -> Map.put(base, "tool_calls", Enum.map(tool_calls, &format_tool_call/1))
    end
  end

  defp format_tool_call(%PhoenixAI.ToolCall{} = tc) do
    %{
      "id" => tc.id,
      "type" => "function",
      "function" => %{
        "name" => tc.name,
        "arguments" => Jason.encode!(tc.arguments)
      }
    }
  end

  defp parse_tool_calls(%{"tool_calls" => tool_calls}) when is_list(tool_calls) do
    Enum.map(tool_calls, fn tc ->
      %PhoenixAI.ToolCall{
        id: tc["id"],
        name: get_in(tc, ["function", "name"]),
        arguments: parse_arguments(get_in(tc, ["function", "arguments"]))
      }
    end)
  end

  defp parse_tool_calls(_), do: []

  defp parse_arguments(args) when is_binary(args) do
    case Jason.decode(args) do
      {:ok, parsed} -> parsed
      {:error, _} -> %{"raw" => args}
    end
  end

  defp parse_arguments(_), do: %{}

  defp extract_error(%{"error" => %{"message" => message}}), do: message
  defp extract_error(body) when is_map(body), do: inspect(body)
  defp extract_error(body) when is_binary(body), do: body

  defp base_url(opts), do: opts[:base_url] || @base_url

  defp maybe_add(map, _key, nil), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)

  defp merge_provider_options(body, nil), do: body
  defp merge_provider_options(body, options) when is_map(options), do: Map.merge(body, options)
end
```

- [ ] **Step 5: Run OpenAI tests to verify they pass**

Run: `mix test test/phoenix_ai/providers/openai_test.exs`

Expected: All 4 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_ai/providers/openai.ex test/phoenix_ai/providers/openai_test.exs \
  test/support/fixtures/openai/
git commit -m "feat: add OpenAI provider adapter with fixture tests"
```

---

### Task 6: AI Facade & Provider Resolution

**Files:**
- Create: `lib/ai.ex`
- Create: `test/phoenix_ai/ai_test.exs`
- Create: `test/test_helper.exs` (update)

- [ ] **Step 1: Update test_helper.exs with Mox setup**

Replace `test/test_helper.exs`:

```elixir
Mox.defmock(PhoenixAI.MockProvider, for: PhoenixAI.Provider)

ExUnit.start()
```

- [ ] **Step 2: Write failing test for AI facade**

Create `test/phoenix_ai/ai_test.exs`:

```elixir
defmodule AITest do
  use ExUnit.Case, async: true

  import Mox

  setup :verify_on_exit!

  describe "chat/2" do
    test "delegates to mock provider" do
      expect(PhoenixAI.MockProvider, :chat, fn messages, opts ->
        assert [%PhoenixAI.Message{role: :user, content: "Hi"}] = messages
        assert opts[:model] == "test-model"
        {:ok, %PhoenixAI.Response{content: "Hello!"}}
      end)

      result =
        AI.chat(
          [%PhoenixAI.Message{role: :user, content: "Hi"}],
          provider: PhoenixAI.MockProvider,
          model: "test-model",
          api_key: "test-key"
        )

      assert {:ok, %PhoenixAI.Response{content: "Hello!"}} = result
    end

    test "resolves :openai atom to OpenAI module" do
      assert AI.provider_module(:openai) == PhoenixAI.Providers.OpenAI
    end

    test "resolves :anthropic atom to Anthropic module" do
      assert AI.provider_module(:anthropic) == PhoenixAI.Providers.Anthropic
    end

    test "resolves :openrouter atom to OpenRouter module" do
      assert AI.provider_module(:openrouter) == PhoenixAI.Providers.OpenRouter
    end

    test "passes through custom module directly" do
      assert AI.provider_module(PhoenixAI.MockProvider) == PhoenixAI.MockProvider
    end

    test "returns error for unknown provider atom" do
      result =
        AI.chat(
          [%PhoenixAI.Message{role: :user, content: "Hi"}],
          provider: :unknown_provider,
          api_key: "test"
        )

      assert {:error, {:unknown_provider, :unknown_provider}} = result
    end

    test "returns error when api_key is missing" do
      # Ensure no env var or config is set
      System.delete_env("OPENAI_API_KEY")
      Application.delete_env(:phoenix_ai, :openai)

      result =
        AI.chat(
          [%PhoenixAI.Message{role: :user, content: "Hi"}],
          provider: :openai
        )

      assert {:error, {:missing_api_key, :openai}} = result
    end
  end
end
```

- [ ] **Step 3: Run test to verify it fails**

Run: `mix test test/phoenix_ai/ai_test.exs`

Expected: FAIL — `AI` module not found.

- [ ] **Step 4: Implement AI facade**

Create `lib/ai.ex`:

```elixir
defmodule AI do
  @moduledoc """
  Thin facade for interacting with AI providers.

  ## Usage

      AI.chat(
        [%PhoenixAI.Message{role: :user, content: "Hello"}],
        provider: :openai,
        model: "gpt-4o"
      )

  ## Configuration Cascade

  Options resolve in order: call-site > config.exs > env vars > provider defaults.
  """

  alias PhoenixAI.Config

  @known_providers [:openai, :anthropic, :openrouter]

  @doc """
  Send messages to an AI provider and receive a response.

  Returns `{:ok, %PhoenixAI.Response{}}` or `{:error, reason}`.
  """
  @spec chat([PhoenixAI.Message.t()], keyword()) ::
          {:ok, PhoenixAI.Response.t()} | {:error, term()}
  def chat(messages, opts \\ []) do
    provider_atom = opts[:provider] || default_provider()

    case resolve_provider(provider_atom) do
      {:ok, provider_mod} ->
        merged_opts = Config.resolve(provider_atom, Keyword.delete(opts, :provider))

        case merged_opts[:api_key] do
          nil -> {:error, {:missing_api_key, provider_atom}}
          _key -> provider_mod.chat(messages, merged_opts)
        end

      {:error, _} = error ->
        error
    end
  end

  @doc "Resolve a provider atom or module to the provider module."
  @spec provider_module(atom()) :: module()
  def provider_module(:openai), do: PhoenixAI.Providers.OpenAI
  def provider_module(:anthropic), do: PhoenixAI.Providers.Anthropic
  def provider_module(:openrouter), do: PhoenixAI.Providers.OpenRouter
  def provider_module(mod) when is_atom(mod), do: mod

  defp resolve_provider(provider) when provider in @known_providers do
    {:ok, provider_module(provider)}
  end

  defp resolve_provider(mod) when is_atom(mod) do
    if Code.ensure_loaded?(mod) and function_exported?(mod, :chat, 2) do
      {:ok, mod}
    else
      {:error, {:unknown_provider, mod}}
    end
  end

  defp default_provider do
    Application.get_env(:phoenix_ai, :default_provider, :openai)
  end
end
```

- [ ] **Step 5: Run AI facade tests to verify they pass**

Run: `mix test test/phoenix_ai/ai_test.exs`

Expected: All 7 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/ai.ex test/phoenix_ai/ai_test.exs test/test_helper.exs
git commit -m "feat: add AI facade with provider resolution and config cascade"
```

---

### Task 7: Supervision child_spec

**Files:**
- Modify: `lib/phoenix_ai/phoenix_ai.ex`

- [ ] **Step 1: Replace the generated phoenix_ai.ex with child_spec**

Replace `lib/phoenix_ai/phoenix_ai.ex` (the one `mix new` created as `lib/phoenix_ai.ex` — move it first):

```bash
# If mix new created lib/phoenix_ai.ex, move it
mv lib/phoenix_ai.ex lib/phoenix_ai/phoenix_ai.ex 2>/dev/null || true
```

Write `lib/phoenix_ai/phoenix_ai.ex`:

```elixir
defmodule PhoenixAI do
  @moduledoc """
  PhoenixAI — AI integration library for Elixir.

  ## Supervision

  Add `PhoenixAI.child_spec()` to your application's supervision tree:

      def start(_type, _args) do
        children = [
          PhoenixAI.child_spec(),
          # ... your other children
        ]
        Supervisor.start_link(children, strategy: :one_for_one)
      end

  This starts a Finch HTTP pool used for streaming in later phases.
  The library never auto-starts processes.
  """

  @doc """
  Returns a child spec for the PhoenixAI supervision subtree.

  ## Options

  - `:finch_name` — Name for the Finch pool (default: `PhoenixAI.Finch`)
  """
  def child_spec(opts \\ []) do
    finch_name = Keyword.get(opts, :finch_name, PhoenixAI.Finch)

    children = [
      {Finch, name: finch_name}
    ]

    %{
      id: __MODULE__,
      start: {Supervisor, :start_link, [children, [strategy: :one_for_one]]},
      type: :supervisor
    }
  end
end
```

- [ ] **Step 2: Verify compilation**

Run: `mix compile`

Expected: Compiles with 0 errors, 0 warnings.

- [ ] **Step 3: Commit**

```bash
git add lib/phoenix_ai/phoenix_ai.ex
git commit -m "feat: add PhoenixAI.child_spec for consumer supervision tree"
```

---

### Task 8: CI & Quality Tools Setup

**Files:**
- Create: `.credo.exs`
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Create .credo.exs**

Create `.credo.exs`:

```elixir
%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      plugins: [],
      requires: [],
      strict: false,
      parse_timeout: 5000,
      color: true
    }
  ]
}
```

- [ ] **Step 2: Create GitHub Actions CI workflow**

Create `.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [master, main]
  pull_request:
    branches: [master, main]

env:
  MIX_ENV: test

jobs:
  test:
    name: Test (Elixir ${{ matrix.elixir }} / OTP ${{ matrix.otp }})
    runs-on: ubuntu-latest
    strategy:
      matrix:
        elixir: ['1.18']
        otp: ['27']
    steps:
      - uses: actions/checkout@v4

      - uses: erlef/setup-beam@v1
        with:
          elixir-version: ${{ matrix.elixir }}
          otp-version: ${{ matrix.otp }}

      - name: Cache deps
        uses: actions/cache@v4
        with:
          path: |
            deps
            _build
          key: ${{ runner.os }}-mix-${{ matrix.elixir }}-${{ matrix.otp }}-${{ hashFiles('mix.lock') }}
          restore-keys: ${{ runner.os }}-mix-${{ matrix.elixir }}-${{ matrix.otp }}-

      - run: mix deps.get
      - run: mix compile --warnings-as-errors
      - run: mix format --check-formatted
      - run: mix credo --strict
      - run: mix test

  dialyzer:
    name: Dialyzer
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.18'
          otp-version: '27'

      - name: Cache deps
        uses: actions/cache@v4
        with:
          path: |
            deps
            _build
          key: ${{ runner.os }}-mix-dialyzer-${{ hashFiles('mix.lock') }}
          restore-keys: ${{ runner.os }}-mix-dialyzer-

      - name: Cache PLTs
        uses: actions/cache@v4
        with:
          path: priv/plts
          key: ${{ runner.os }}-plts-${{ hashFiles('mix.lock') }}
          restore-keys: ${{ runner.os }}-plts-

      - run: mix deps.get
      - run: mix dialyzer
```

- [ ] **Step 3: Run quality checks locally**

Run: `mix format && mix credo`

Expected: No formatting issues, no Credo warnings.

- [ ] **Step 4: Commit**

```bash
git add .credo.exs .github/
git commit -m "chore: add CI pipeline and Credo config"
```

---

### Task 9: Final Integration Verification

- [ ] **Step 1: Run full test suite**

Run: `mix test`

Expected: All tests PASS (approximately 22 tests).

- [ ] **Step 2: Run format check**

Run: `mix format --check-formatted`

Expected: No formatting issues.

- [ ] **Step 3: Run Credo**

Run: `mix credo`

Expected: No issues or only informational messages.

- [ ] **Step 4: Verify compilation with warnings as errors**

Run: `mix compile --warnings-as-errors`

Expected: Compiles with 0 errors, 0 warnings.

- [ ] **Step 5: Verify the consumer experience works**

Open `iex -S mix` and run:

```elixir
# Verify structs work
msg = %PhoenixAI.Message{role: :user, content: "Hello"}
# => %PhoenixAI.Message{role: :user, content: "Hello", ...}

# Verify provider resolution works
AI.provider_module(:openai)
# => PhoenixAI.Providers.OpenAI

# Verify config resolution works
PhoenixAI.Config.resolve(:openai, api_key: "test", model: "gpt-4o")
# => [model: "gpt-4o", api_key: "test"]

# Verify missing api_key is caught
AI.chat([msg], provider: :openai)
# => {:error, {:missing_api_key, :openai}}
```

- [ ] **Step 6: Final commit if any formatting adjustments were needed**

```bash
git add -A
git commit -m "chore: phase 1 final integration verification"
```

---

## Summary

| Task | What it delivers | Tests |
|------|-----------------|-------|
| 1. Mix Project Scaffold | `mix.exs`, deps, formatters, gitignore | Compilation |
| 2. Data Model Structs | Message, Response, ToolCall, ToolResult, Error, stubs | 8 tests |
| 3. Provider Behaviour | `PhoenixAI.Provider` behaviour contract | Compilation |
| 4. Config Resolution | `PhoenixAI.Config.resolve/2` cascade | 8 tests |
| 5. OpenAI Adapter | `PhoenixAI.Providers.OpenAI` with fixtures | 4 tests |
| 6. AI Facade | `AI.chat/2` with provider resolution | 7 tests |
| 7. Supervision child_spec | `PhoenixAI.child_spec/1` | Compilation |
| 8. CI & Quality Tools | GitHub Actions, Credo config | Format + Credo pass |
| 9. Integration Verification | Full suite green, iex smoke test | All ~22 tests |

**Total estimated tests:** ~27
**Commits:** 9 atomic commits
