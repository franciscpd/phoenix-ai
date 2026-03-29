# Phase 1: Core Foundation — Design Spec

**Date:** 2026-03-29
**Status:** Approved
**Approach:** Thin AI Facade (Approach A)

## Overview

Phase 1 establishes the library's structural skeleton: canonical data model structs, Provider behaviour contract, HTTP transport (Req for sync requests), a working OpenAI adapter, call-site configuration with env var fallback, and child_spec for consumer supervision tree integration.

## Architecture

### Approach: Thin AI Facade

The `AI` module is a thin facade (~60 lines) that:
1. Resolves provider atoms (`:openai`) to provider modules (`PhoenixAI.Providers.OpenAI`)
2. Merges config in cascade: call-site opts > config.exs > `System.get_env` > provider defaults
3. Delegates to `provider_mod.chat(messages, merged_opts)`

Also accepts a module directly (`provider: MyApp.CustomProvider`) for custom providers without a registry.

### Why This Approach

- Simplest viable architecture — no GenServer, no registry, no protocol
- Follows the pattern validated by Swoosh, ReqLLM, and ex_llm
- Avoids Pitfall #7 (supervision pollution) and Pitfall #10 (protocol misuse)
- Registry pattern can be added in v2 if runtime extensibility is needed

## Data Model

### PhoenixAI.Message

```elixir
@type role :: :system | :user | :assistant | :tool
@type t :: %__MODULE__{
  role: role(),
  content: String.t() | nil,
  tool_call_id: String.t() | nil,
  tool_calls: [PhoenixAI.ToolCall.t()] | nil,
  metadata: map()
}
defstruct [:role, :content, :tool_call_id, :tool_calls, metadata: %{}]
```

### PhoenixAI.Response

```elixir
@type t :: %__MODULE__{
  content: String.t() | nil,
  tool_calls: [PhoenixAI.ToolCall.t()],
  usage: map(),
  finish_reason: String.t() | nil,
  model: String.t() | nil,
  provider_response: map()
}
defstruct [:content, :finish_reason, :model, tool_calls: [], usage: %{}, provider_response: %{}]
```

- `provider_response` is the escape hatch — raw provider response for anything the abstraction doesn't cover
- `usage` is a generic map to accommodate different provider usage formats

### PhoenixAI.ToolCall

```elixir
@type t :: %__MODULE__{id: String.t(), name: String.t(), arguments: map()}
defstruct [:id, :name, arguments: %{}]
```

### PhoenixAI.ToolResult

```elixir
@type t :: %__MODULE__{tool_call_id: String.t(), content: String.t(), error: String.t() | nil}
defstruct [:tool_call_id, :content, :error]
```

### PhoenixAI.Error

```elixir
@type t :: %__MODULE__{status: integer() | nil, message: String.t(), provider: atom()}
defstruct [:status, :message, :provider]
```

### Stubs (defined in Phase 1, implemented in later phases)

- `PhoenixAI.Conversation` — struct defined with `id`, `messages`, `metadata` fields. Used from Phase 4.
- `PhoenixAI.StreamChunk` — struct defined with `delta`, `tool_call_delta`, `finish_reason` fields. Used from Phase 6.

## Provider Behaviour Contract

```elixir
defmodule PhoenixAI.Provider do
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

### Design Rationale

- `chat/2` is the only required callback for v1 — a minimal provider only needs this
- `parse_response/1` is required and separate from `chat/2` for testability: load a JSON fixture, call `parse_response/1`, validate parsing without HTTP
- `stream/3`, `format_tools/1`, `parse_chunk/1` are optional — providers that don't support streaming or tools skip these
- Providers that are OpenAI-compatible (like OpenRouter) can delegate to the OpenAI adapter with a different base URL

## Configuration Resolution

### Cascade Order

```
1. Call-site opts     AI.chat(msgs, api_key: "sk-xxx", model: "gpt-4o")
2. config.exs         config :phoenix_ai, :openai, api_key: "sk-yyy"
3. System.get_env      OPENAI_API_KEY, ANTHROPIC_API_KEY, OPENROUTER_API_KEY
4. Provider defaults   model: "gpt-4o" (OpenAI), "claude-sonnet-4-5" (Anthropic)
```

Call-site always wins. This enables multi-tenant usage from v1.

### Env Var Mapping

| Provider | Env Var | Config Key |
|----------|---------|------------|
| `:openai` | `OPENAI_API_KEY` | `config :phoenix_ai, :openai, api_key:` |
| `:anthropic` | `ANTHROPIC_API_KEY` | `config :phoenix_ai, :anthropic, api_key:` |
| `:openrouter` | `OPENROUTER_API_KEY` | `config :phoenix_ai, :openrouter, api_key:` |

### Default Models

| Provider | Default Model |
|----------|---------------|
| `:openai` | `"gpt-4o"` |
| `:anthropic` | `"claude-sonnet-4-5"` (no date suffix) |
| `:openrouter` | None — must be explicit |

### Config Module

`PhoenixAI.Config` handles the merge logic. Extracted from `AI` to keep the facade thin and the merge logic testable independently.

## OpenAI Adapter

`PhoenixAI.Providers.OpenAI` implements the Provider behaviour:

- **Owns its HTTP** — calls `Req.post/2` directly. No shared HTTP layer.
- **Base URL configurable** — `base_url` option for proxies or OpenAI-compatible APIs.
- **`provider_options` merge** — `Map.merge(body, opts[:provider_options] || %{})` passes provider-specific params (logprobs, seed, response_format) directly into the request body.
- **Error handling** — non-200 responses return `{:error, %PhoenixAI.Error{}}` with status, message, and provider atom.
- **Message formatting** — converts `PhoenixAI.Message` structs to OpenAI's `%{role: "...", content: "..."}` format.

## Supervision

```elixir
defmodule PhoenixAI do
  def child_spec(opts \\ []) do
    children = [
      {Finch, name: opts[:finch_name] || PhoenixAI.Finch}
    ]
    %{
      id: __MODULE__,
      start: {Supervisor, :start_link, [children, [strategy: :one_for_one]]},
      type: :supervisor
    }
  end
end
```

- Library NEVER defines `use Application` — no auto-starting processes
- Consumer opts in by adding `PhoenixAI.child_spec()` to their supervision tree
- Only Finch is started (needed for streaming in Phase 6, initialized early to avoid breaking changes)
- Finch pool name is configurable for consumers who already use Finch

## Project Structure

```
phoenix_ai/
├── mix.exs                          # deps: req, jason, nimble_options, telemetry, finch
├── .formatter.exs
├── .credo.exs
├── .github/workflows/ci.yml        # mix test, format --check, credo, dialyzer
├── lib/
│   ├── ai.ex                        # AI facade (~60 lines)
│   └── phoenix_ai/
│       ├── phoenix_ai.ex            # child_spec, top-level module
│       ├── config.ex                # Config resolution logic
│       ├── error.ex                 # %PhoenixAI.Error{}
│       ├── message.ex               # %PhoenixAI.Message{}
│       ├── response.ex              # %PhoenixAI.Response{}
│       ├── tool_call.ex             # %PhoenixAI.ToolCall{}
│       ├── tool_result.ex           # %PhoenixAI.ToolResult{}
│       ├── conversation.ex          # %PhoenixAI.Conversation{} (stub)
│       ├── stream_chunk.ex          # %PhoenixAI.StreamChunk{} (stub)
│       ├── provider.ex              # @behaviour PhoenixAI.Provider
│       └── providers/
│           └── openai.ex            # PhoenixAI.Providers.OpenAI
├── test/
│   ├── test_helper.exs              # Mox setup
│   ├── support/fixtures/openai/     # Recorded JSON responses
│   │   ├── chat_completion.json
│   │   └── chat_error_401.json
│   └── phoenix_ai/
│       ├── ai_test.exs              # Facade integration (Mox)
│       ├── config_test.exs          # Config resolution
│       ├── message_test.exs         # Struct tests
│       ├── response_test.exs
│       └── providers/
│           └── openai_test.exs      # Mox + fixture tests
└── config/
    └── config.exs
```

## Testing Strategy

### Two-Layer Testing

1. **Mox layer (unit):** Tests that the AI facade delegates correctly. Mock the Provider behaviour, verify calls.
2. **Fixture layer (integration without HTTP):** Tests that the OpenAI adapter parses real provider responses correctly. Load recorded JSON, call `parse_response/1`, validate struct fields.

### What Gets Tested

| Component | Strategy | Coverage |
|-----------|----------|----------|
| AI facade | Mox mock of Provider behaviour | Delegation, config merge, provider resolution |
| Config resolution | Unit tests with controlled env | Cascade order, env fallback, defaults |
| Data model structs | Unit tests | Construction, field validation, typespec |
| OpenAI adapter `parse_response/1` | Fixture JSON files | Response parsing, error extraction, tool call parsing |
| OpenAI adapter `chat/2` | Mox (no real HTTP) | Request formatting, header construction, error handling |

### Mox Setup

```elixir
# test/test_helper.exs
Mox.defmock(PhoenixAI.MockProvider, for: PhoenixAI.Provider)
ExUnit.start()
```

## Dependencies (mix.exs)

```elixir
defp deps do
  [
    {:req, "~> 0.5"},
    {:jason, "~> 1.4"},
    {:nimble_options, "~> 1.1"},
    {:telemetry, "~> 1.3"},
    {:finch, "~> 0.19"},

    # Dev/test only
    {:mox, "~> 1.2", only: :test},
    {:excoveralls, "~> 0.18", only: :test},
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
    {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
    {:ex_doc, "~> 0.34", only: :dev, runtime: false}
  ]
end
```

All runtime deps use `~> major.minor` pins (not patch-level) per Pitfall #12.

## Error Handling

- All public functions return `{:ok, result}` or `{:error, reason}` — never raise
- Provider errors wrapped in `%PhoenixAI.Error{status:, message:, provider:}`
- Unknown provider atom returns `{:error, {:unknown_provider, atom}}`
- Missing API key returns `{:error, {:missing_api_key, provider_atom}}`

## Out of Scope for Phase 1

- Anthropic and OpenRouter adapters (Phase 2)
- Tool calling loop (Phase 3)
- Agent GenServer (Phase 4)
- Streaming (Phase 6)
- NimbleOptions validation on public functions (Phase 10 — schemas stabilize late)
- Telemetry events (Phase 10)

---
*Design approved: 2026-03-29*
*Phase: 01-core-foundation*
