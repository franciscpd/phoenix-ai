# Phase 10: Developer Experience — Design Spec

**Date:** 2026-03-31
**Phase:** 10-developer-experience
**Approach:** Incremental Layering — additive changes over existing code, no logic rewrites
**Requirements:** DX-01, DX-02, DX-03, DX-04, DX-05

## Overview

Phase 10 wraps the existing PhoenixAI library with developer-facing quality: a TestProvider for offline testing, telemetry instrumentation for observability, NimbleOptions schemas for option validation, ExDoc guides with cookbook recipes, and Hex publish readiness. No new runtime capabilities — this phase makes what exists production-grade and developer-friendly.

**Implementation order:** TestProvider → Telemetry → NimbleOptions → ExDoc & Hex

Each layer builds on the previous: TestProvider enables offline tests for telemetry instrumentation, NimbleOptions uses TestProvider in its validation tests, ExDoc documents the final API surface including NimbleOptions-generated option docs.

---

## 1. TestProvider (DX-01)

### Files

- `lib/phoenix_ai/providers/test_provider.ex` — Provider behaviour implementation
- `lib/phoenix_ai/test.ex` — ExUnit helper macros

### Architecture

TestProvider is a **real provider adapter** implementing `PhoenixAI.Provider`. It dispatches via the standard `AI.chat(msgs, provider: :test)` path — same code path as production providers.

State is stored in an `Agent` process keyed by the calling test's PID. This ensures async ExUnit test isolation — each test owns its own response queue/handler.

### Dispatch Integration

`AI.provider_module(:test)` returns `PhoenixAI.Providers.TestProvider`. Add `:test` to `@known_providers` in `AI` module.

### Modes

**Queue (FIFO):** Pre-defined responses consumed in order. Each `chat/2` call pops the next response.

```elixir
PhoenixAI.Test.set_responses([
  {:ok, %Response{content: "First", usage: %{total_tokens: 10}}},
  {:ok, %Response{content: "Second"}}
])

{:ok, resp1} = AI.chat(msgs, provider: :test)  # "First"
{:ok, resp2} = AI.chat(msgs, provider: :test)  # "Second"
```

When the queue is exhausted, returns `{:error, :no_more_responses}`.

**Handler (function):** Custom logic receives messages and opts, returns response.

```elixir
PhoenixAI.Test.set_handler(fn messages, _opts ->
  last = List.last(messages)
  {:ok, %Response{content: "Echo: #{last.content}"}}
end)
```

Handler takes precedence over queue when both are set.

### ExUnit Helper (`use PhoenixAI.Test`)

The `__using__` macro:
1. Registers an `on_exit` callback to clean up the Agent state for the test PID
2. Imports `set_responses/1`, `set_handler/1`
3. Provides `assert_called/1` to verify the provider was called — TestProvider records each `{messages, opts}` tuple it receives, and `assert_called/1` pattern-matches against the call log

### Stream Support

TestProvider implements `stream/3` by emitting scripted response content as synthetic `%StreamChunk{}` structs to the callback, simulating SSE delivery. This allows testing stream consumers without network calls.

### Provider Behaviour Callbacks

| Callback | Implementation |
|---|---|
| `chat/2` | Pop from queue or call handler |
| `stream/3` | Emit chunks from queue response via callback |
| `parse_response/1` | Identity — responses are already `%Response{}` |
| `format_tools/1` | Pass through — tools are already formatted for testing |
| `parse_chunk/1` | Not needed — TestProvider generates chunks directly |

---

## 2. Telemetry (DX-02)

### Event Naming Convention

All events follow `[:phoenix_ai, resource, action]`, consistent with Phoenix, Ecto, and Oban conventions.

### Span Events (`:telemetry.span/3`)

Spans measure duration automatically and emit `:start`, `:stop`, `:exception` events.

| Event Prefix | Location | Start Metadata | Stop Metadata (additional) |
|---|---|---|---|
| `[:phoenix_ai, :chat]` | `AI.chat/2` | `%{provider: atom, model: string}` | `%{usage: map, status: :ok \| :error}` |
| `[:phoenix_ai, :stream]` | `AI.stream/2` | `%{provider: atom, model: string}` | `%{usage: map, chunk_count: int, status: :ok \| :error}` |
| `[:phoenix_ai, :agent, :prompt]` | `Agent.prompt/2` (inside GenServer) | `%{provider: atom, model: string}` | `%{usage: map, tool_calls_count: int, status: :ok \| :error}` |

### Discrete Events (`:telemetry.execute/3`)

Discrete events fire at specific points without duration tracking (the caller measures if needed).

| Event | Location | Metadata |
|---|---|---|
| `[:phoenix_ai, :tool_call, :start]` | `ToolLoop.execute_tool/3` before execution | `%{tool: string}` |
| `[:phoenix_ai, :tool_call, :stop]` | `ToolLoop.execute_tool/3` after execution | `%{tool: string, duration_ms: int, status: :ok \| :error}` |
| `[:phoenix_ai, :pipeline, :step]` | `Pipeline.run/3` after each step | `%{step_index: int, step_name: atom \| nil, status: :ok \| :error, duration_ms: int}` |
| `[:phoenix_ai, :team, :complete]` | `Team.run/3` after merge | `%{agent_count: int, success_count: int, error_count: int, duration_ms: int}` |

### Instrumentation Pattern

```elixir
# Span wrapping in AI.chat/2
def chat(messages, opts) do
  meta = %{provider: provider_atom, model: opts[:model]}
  :telemetry.span([:phoenix_ai, :chat], meta, fn ->
    result = do_chat(messages, validated_opts)
    stop_meta = Map.merge(meta, extract_usage(result))
    {result, stop_meta}
  end)
end

# Discrete event in ToolLoop
defp execute_tool(tool_call, tools, opts) do
  start_time = System.monotonic_time()
  :telemetry.execute([:phoenix_ai, :tool_call, :start], %{}, %{tool: tool_call.name})
  result = do_execute(tool_call, tools, opts)
  duration = System.monotonic_time() - start_time
  :telemetry.execute([:phoenix_ai, :tool_call, :stop], %{duration: duration}, %{tool: tool_call.name, status: status(result)})
  result
end
```

### Zero Overhead

Telemetry events are fire-and-forget. If no handler is attached, the cost is a function call to `:telemetry.execute/3` which returns immediately. No state accumulation, no process messaging.

---

## 3. NimbleOptions (DX-03)

### Schema Locations

Each public module defines its schema locally via `@schema_name NimbleOptions.new!(...)` module attribute.

| Module | Schema | Validates |
|---|---|---|
| `AI` | `@chat_schema` | `AI.chat/2` opts |
| `AI` | `@stream_schema` | `AI.stream/2` opts |
| `Agent` | `@start_schema` | `Agent.start_link/1` opts |
| `Pipeline` | `@run_schema` | `Pipeline.run/3` opts (minimal) |
| `Team` | `@run_schema` | `Team.run/3` opts |

### AI Chat Schema

```elixir
@chat_schema NimbleOptions.new!([
  provider: [
    type: :atom,
    doc: "Provider identifier (:openai, :anthropic, :openrouter, :test)"
  ],
  model: [
    type: :string,
    doc: "Model identifier (e.g., \"gpt-4o\", \"claude-sonnet-4-5\")"
  ],
  api_key: [
    type: :string,
    doc: "API key — overrides config/env resolution"
  ],
  temperature: [
    type: :float,
    doc: "Sampling temperature (0.0-2.0)"
  ],
  max_tokens: [
    type: :pos_integer,
    doc: "Maximum tokens in response"
  ],
  tools: [
    type: {:list, :atom},
    default: [],
    doc: "Tool modules implementing PhoenixAI.Tool"
  ],
  schema: [
    type: :any,
    doc: "JSON schema map for structured output validation"
  ],
  provider_options: [
    type: {:map, :atom, :any},
    default: %{},
    doc: "Provider-specific options passed through untouched"
  ]
])
```

### AI Stream Schema (extends chat)

Same as chat plus:

```elixir
on_chunk: [
  type: {:fun, 1},
  doc: "Callback function receiving %StreamChunk{} structs"
],
to: [
  type: :pid,
  doc: "PID to receive {:phoenix_ai, {:chunk, chunk}} messages"
]
```

### Agent Start Schema

```elixir
@start_schema NimbleOptions.new!([
  provider: [type: :atom, required: true, doc: "Provider identifier"],
  model: [type: :string, doc: "Model identifier"],
  system: [type: :string, doc: "System prompt"],
  tools: [type: {:list, :atom}, default: [], doc: "Tool modules"],
  manage_history: [type: :boolean, default: true, doc: "Auto-accumulate messages between prompts"],
  schema: [type: :any, doc: "JSON schema for structured output"],
  name: [type: :any, doc: "GenServer name registration"],
  api_key: [type: :string, doc: "API key"]
])
```

### Team Run Schema

```elixir
@run_schema NimbleOptions.new!([
  max_concurrency: [type: :pos_integer, default: 5, doc: "Max parallel tasks"],
  timeout: [type: {:or, [:pos_integer, {:in, [:infinity]}]}, default: :infinity, doc: "Per-task timeout in ms"],
  ordered: [type: :boolean, default: true, doc: "Preserve input order in results"]
])
```

### Validation Pattern

```elixir
def chat(messages, opts \\ []) do
  case NimbleOptions.validate(opts, @chat_schema) do
    {:ok, validated_opts} -> do_chat(messages, validated_opts)
    {:error, %NimbleOptions.ValidationError{} = error} -> {:error, error}
  end
end
```

No raises — returns `{:error, _}` tuple consistent with CORE-05.

### ExDoc Integration

`NimbleOptions.docs(@chat_schema)` generates markdown option documentation, included in `@doc` via string interpolation. This keeps docs always in sync with validation rules.

---

## 4. ExDoc & Hex Publish (DX-04, DX-05)

### Guide Structure

```
guides/
├── getting-started.md        — Install, configure, first AI.chat call
├── provider-setup.md         — OpenAI, Anthropic, OpenRouter, TestProvider config
├── agents-and-tools.md       — Agent GenServer, Tool behaviour, tool loop
├── pipelines-and-teams.md    — Pipeline DSL, Team DSL, composition
└── cookbook/
    ├── rag-pipeline.md       — Search → summarize → respond using Pipeline
    ├── multi-agent-team.md   — Parallel agents with Team, merging results
    ├── streaming-liveview.md — Stream to LiveView via `to: self()` + handle_info
    └── custom-tools.md       — Building Tool modules, schemas, error handling
```

### Guide Content Summary

**Getting Started:** Installation (`{:phoenix_ai, "~> 0.1"}`), config.exs setup, env vars, first `AI.chat/2` call, understanding `%Response{}`.

**Provider Setup:** Per-provider configuration (API keys, models, base URLs), `provider_options:` escape hatch, TestProvider for testing, how config cascade works.

**Agents & Tools:** Tool behaviour (`name/0`, `description/0`, `parameters_schema/0`, `execute/2`), Agent GenServer lifecycle, `prompt/2` loop, `manage_history` modes, supervision.

**Pipelines & Teams:** Pipeline `step/2` DSL, ad-hoc `Pipeline.run/3`, Team `agent/2` + `merge/1` DSL, ad-hoc `Team.run/3`, composition (Pipeline step that calls Team).

**Cookbook recipes:** Real-world patterns with complete code examples. Each recipe is self-contained and copy-pasteable.

### mix.exs Docs Configuration

```elixir
defp docs do
  [
    main: "getting-started",
    extras: [
      "guides/getting-started.md",
      "guides/provider-setup.md",
      "guides/agents-and-tools.md",
      "guides/pipelines-and-teams.md",
      "guides/cookbook/rag-pipeline.md",
      "guides/cookbook/multi-agent-team.md",
      "guides/cookbook/streaming-liveview.md",
      "guides/cookbook/custom-tools.md"
    ],
    groups_for_extras: [
      "Guides": ~r/guides\/[^\/]+\.md$/,
      "Cookbook": ~r/guides\/cookbook\/.+\.md$/
    ],
    groups_for_modules: [
      "Core": [AI, PhoenixAI.Message, PhoenixAI.Response, PhoenixAI.Conversation],
      "Providers": [~r/PhoenixAI\.Providers\./],
      "Tools & Agent": [PhoenixAI.Tool, PhoenixAI.Agent, PhoenixAI.ToolLoop],
      "Orchestration": [PhoenixAI.Pipeline, PhoenixAI.Team],
      "Streaming": [PhoenixAI.Stream, PhoenixAI.StreamChunk],
      "Schema & Config": [PhoenixAI.Schema, PhoenixAI.Config],
      "Testing": [PhoenixAI.Test, PhoenixAI.Providers.TestProvider]
    ]
  ]
end
```

### Hex Publish Readiness

| Item | Status |
|---|---|
| `description` in mix.exs | Already set |
| `package/0` with licenses, links | Already configured |
| `deps` with `~> major.minor` pins | Already in place |
| `files:` in package (exclude .planning/, test/) | Needs adding |
| README.md with badges | Needs updating |
| `@version "0.1.0"` | Already set |
| All `@moduledoc` on public modules | Needs adding/improving |
| All `@doc` + `@spec` on public functions | Partially done, needs completion |

### Moduledoc Standard

Every public module:
- One-line `@moduledoc` summary
- Usage example (copy-pasteable)
- Options table (NimbleOptions-generated where applicable)
- Link to relevant guide

Every public function:
- `@doc` with description and example
- `@spec` typespec

---

## 5. Testing Strategy

### TestProvider Tests
- Queue mode: set N responses, call N times, verify order
- Handler mode: set handler, verify messages/opts received
- Queue exhausted: returns `{:error, :no_more_responses}`
- Stream mode: scripted chunks delivered to callback
- Async isolation: two concurrent tests with different responses don't interfere
- `assert_called/1`: verify provider was invoked with expected messages

### Telemetry Tests
- Attach handler, call `AI.chat/2` with TestProvider, assert start/stop events fired
- Assert metadata contains provider, model, usage
- Assert exception event fires on provider error
- Assert tool_call events fire during tool loop
- Assert pipeline step events fire in order
- Assert team complete event fires with correct counts

### NimbleOptions Tests
- Valid opts pass through unchanged
- Invalid type returns `{:error, %NimbleOptions.ValidationError{}}`
- Missing required opts return clear error
- Unknown opts return error (not silently ignored)
- Default values applied correctly
- Each public API entry point validates

### ExDoc Tests
- `mix docs` compiles without warnings
- All public modules have `@moduledoc`
- All public functions have `@doc`
- Guide links resolve correctly

### Hex Publish Tests
- `mix hex.build` succeeds
- Package includes only intended files
- No secrets or test fixtures in package

---

## 6. Error Handling

- **TestProvider with no responses set:** `{:error, :test_provider_not_configured}`
- **TestProvider queue exhausted:** `{:error, :no_more_responses}`
- **NimbleOptions validation failure:** `{:error, %NimbleOptions.ValidationError{message: "..."}}`
- **Telemetry handler crash:** Does not affect the caller — `:telemetry` catches handler exceptions silently (by design)

---

## Files Changed/Created

### New Files
- `lib/phoenix_ai/providers/test_provider.ex`
- `lib/phoenix_ai/test.ex`
- `guides/getting-started.md`
- `guides/provider-setup.md`
- `guides/agents-and-tools.md`
- `guides/pipelines-and-teams.md`
- `guides/cookbook/rag-pipeline.md`
- `guides/cookbook/multi-agent-team.md`
- `guides/cookbook/streaming-liveview.md`
- `guides/cookbook/custom-tools.md`
- `test/phoenix_ai/providers/test_provider_test.exs`
- `test/phoenix_ai/telemetry_test.exs`
- `test/phoenix_ai/nimble_options_test.exs`

### Modified Files
- `lib/ai.ex` — Add `:test` to providers, add telemetry spans, add NimbleOptions validation
- `lib/phoenix_ai/agent.ex` — Add telemetry span to prompt, add NimbleOptions validation to start_link
- `lib/phoenix_ai/tool_loop.ex` — Add telemetry events for tool execution
- `lib/phoenix_ai/pipeline.ex` — Add telemetry events for steps, add NimbleOptions for run opts
- `lib/phoenix_ai/team.ex` — Add telemetry event for completion, add NimbleOptions for run opts
- `lib/phoenix_ai/stream.ex` — (Telemetry spans are in AI.stream, not here)
- `mix.exs` — Update docs config, add files to package
- `README.md` — Add badges, improve getting started section
