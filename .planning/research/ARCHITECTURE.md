# Architecture Patterns

**Domain:** Elixir AI Integration Library (PhoenixAI)
**Researched:** 2026-03-29
**Reference:** laravel/ai, LangChain.ex, ex_llm, Alloy, ReqLLM, Jido

---

## Recommended Architecture

PhoenixAI should be organized as a layered library where each layer has a single responsibility and communicates only with the layers directly adjacent to it. The layers from bottom to top: HTTP transport, provider adapters, core data model, agent runtime, and public API surface.

```
┌─────────────────────────────────────────────────────────────┐
│                      PUBLIC API LAYER                        │
│              PhoenixAI  (unified entry point)                │
│     .chat/3   .agent/2   .pipeline/2   .stream/3            │
└────────────────────────┬────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────┐
│                    AGENT RUNTIME LAYER                       │
│   PhoenixAI.Agent (GenServer)  PhoenixAI.Pipeline           │
│   PhoenixAI.Team (Task.Supervisor)  conversation state       │
└────────────────────────┬────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────┐
│                  CORE DATA MODEL LAYER                       │
│   Message  Conversation  ToolCall  ToolResult  Response      │
│   Tool (behaviour)   Schema (structured output)              │
└────────────────────────┬────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────┐
│                  PROVIDER ADAPTER LAYER                      │
│   PhoenixAI.Provider (behaviour)                             │
│   Providers.OpenAI   Providers.Anthropic   Providers.OpenRouter │
└────────────────────────┬────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────┐
│                   HTTP TRANSPORT LAYER                       │
│   Req (standard requests)   Finch (SSE streaming)            │
└─────────────────────────────────────────────────────────────┘
```

---

## Component Boundaries

### Component 1: Provider Behaviour (`PhoenixAI.Provider`)

Single responsibility: translate between PhoenixAI's canonical data model and each provider's HTTP API.

| Callback | Purpose |
|----------|---------|
| `chat/2` | Send messages, receive response |
| `stream/3` | Send messages, stream response chunks via callback |
| `format_tools/1` | Serialize Tool structs to provider's schema format |
| `parse_response/1` | Normalize provider HTTP response to canonical Response struct |
| `parse_chunk/1` | Normalize SSE chunk to canonical token or tool-call event |

**Communicates with:** HTTP transport layer (Req/Finch), Core data model layer (receives/returns structs)

**Does NOT know about:** Agent state, pipelines, conversation history, OTP processes

```elixir
defmodule PhoenixAI.Provider do
  @callback chat(messages :: [Message.t()], opts :: keyword()) ::
              {:ok, Response.t()} | {:error, term()}

  @callback stream(messages :: [Message.t()], callback :: (chunk -> any()), opts :: keyword()) ::
              {:ok, Response.t()} | {:error, term()}

  @callback format_tools(tools :: [Tool.t()]) :: [map()]
end
```

**Confidence:** HIGH — this is the canonical Elixir pattern (Swoosh, ReqLLM, ex_llm all validate it). Sources: [Swoosh adapter pattern](https://www.djm.org.uk/posts/writing-extensible-elixir-with-behaviours-adapters-pluggable-backends/), [ReqLLM provider behaviour](https://hexdocs.pm/req_llm/overview.html)

---

### Component 2: Core Data Model

Single responsibility: define the canonical structs that flow through the system. All provider adapters speak this language; no layer bypasses these types.

| Struct | Fields | Purpose |
|--------|--------|---------|
| `Message` | role, content, tool_call_id | Single turn in a conversation |
| `Conversation` | id, messages, metadata | Ordered list of messages with context |
| `ToolCall` | id, name, arguments | LLM's intent to invoke a tool |
| `ToolResult` | tool_call_id, content, error | Output of executing a tool |
| `Response` | content, tool_calls, usage, finish_reason | Canonical provider response |
| `StreamChunk` | delta, tool_call_delta, finish_reason | Single SSE event |

**Communicates with:** All layers (these are the data bus)

**Does NOT know about:** HTTP transport, provider specifics, OTP processes

---

### Component 3: Tool Behaviour (`PhoenixAI.Tool`)

Single responsibility: define the interface that callable functions must implement so the agent loop can discover, serialize, and execute them.

```elixir
defmodule PhoenixAI.Tool do
  @callback name() :: String.t()
  @callback description() :: String.t()
  @callback parameters_schema() :: map()
  @callback execute(params :: map(), context :: map()) ::
              {:ok, term()} | {:error, term()}
end
```

Tools are plain modules implementing this behaviour — no OTP, no GenServer. They are pure functions. The agent runtime dispatches to them; they do not know about the agent.

**Communicates with:** Agent runtime layer (invoked by it), Core data model (returns results that become ToolResult structs)

**Confidence:** HIGH — matches laravel/ai Tool contract and Jido Actions pattern. Sources: [Jido architecture](https://github.com/agentjido/jido), [Laravel AI tools](https://laravel.com/docs/12.x/ai-sdk)

---

### Component 4: Agent Runtime (`PhoenixAI.Agent`)

Single responsibility: run the completion-tool-call loop to completion, maintaining conversation state within a single process.

The agent is a GenServer that owns one conversation's state. It:
1. Holds the current `Conversation` in its state
2. On `prompt/2`, adds the user message, calls the provider
3. If the response contains tool calls, dispatches each via `Tool.execute/2`, collects `ToolResult` structs, appends them, and loops back to the provider
4. When finish_reason is "stop", returns the final response to the caller
5. Can be started under a `DynamicSupervisor` for per-session isolation

```elixir
# Usage pattern
{:ok, pid} = PhoenixAI.Agent.start_link(
  provider: PhoenixAI.Providers.Anthropic,
  model: "claude-3-5-sonnet-20241022",
  system: "You are a helpful assistant.",
  tools: [MyApp.Tools.Search, MyApp.Tools.Calculator]
)

{:ok, response} = PhoenixAI.Agent.prompt(pid, "What is the weather in Lisbon?")
```

**OTP role:** GenServer. Each agent is an isolated process. Crashes are isolated. Supervised by `DynamicSupervisor` at the library or application level.

**Communicates with:** Provider adapter layer (makes chat/stream calls), Tool behaviour implementations (dispatches tool calls), Core data model (reads/writes Message, ToolCall, ToolResult structs)

**Does NOT know about:** Pipeline, Team, public API caller's identity

**Confidence:** HIGH — validated by Alloy, Jido AgentServer, and multiple 2025 Elixir AI tutorials. Sources: [Alloy forum post](https://elixirforum.com/t/alloy-a-minimal-otp-native-ai-agent-engine-for-elixir/74464), [Jido GitHub](https://github.com/agentjido/jido)

---

### Component 5: Streaming Transport

Single responsibility: establish a Finch HTTP connection to an SSE endpoint and emit parsed chunks to a caller-supplied callback or process PID.

**Key decision:** Use Finch directly for streaming, not Req. Req's plugin architecture does not support the long-running, stateful connections required for Server-Sent Events. This is validated by both ReqLLM 1.0 and Fly.io's streaming guide.

```elixir
# Internal — not public API. Used by provider adapters.
defmodule PhoenixAI.HTTP.Stream do
  def stream(url, headers, body, on_chunk) do
    Finch.build(:post, url, headers, body)
    |> Finch.stream(PhoenixAI.Finch, fn
      {:status, status}, acc -> ...
      {:headers, headers}, acc -> ...
      {:data, data}, acc ->
        data
        |> parse_sse_lines()
        |> Enum.each(on_chunk)
        acc
    end)
  end
end
```

**Communicates with:** Provider adapters (called by them), Agent runtime (stream chunks are forwarded to calling process via `send/2` or callback)

**Confidence:** HIGH — explicitly validated by ReqLLM and Fly.io. Sources: [ReqLLM 1.0](https://jido.run/blog/announcing-req_llm-1_0), [Fly.io streaming](https://fly.io/phoenix-files/streaming-openai-responses/)

---

### Component 6: Pipeline Orchestrator (`PhoenixAI.Pipeline`)

Single responsibility: execute a sequence of steps where each step's output becomes the next step's input. Steps can be agent invocations, plain function calls, or tool executions.

This is a pure data transformation — no GenServer needed for the pipeline itself. It uses the pipe operator pattern (`|>`) and `Enum.reduce` with `{:ok, state}` / `{:error, reason}` railway.

```elixir
defmodule PhoenixAI.Pipeline do
  def run(steps, initial_input, opts \\ []) do
    Enum.reduce_while(steps, {:ok, initial_input}, fn step, {:ok, acc} ->
      case step.(acc) do
        {:ok, result} -> {:cont, {:ok, result}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end
end
```

**Communicates with:** Agent runtime (a step may be an `Agent.prompt/2` call), Tool behaviour (a step may be direct tool execution), public API caller

**Confidence:** HIGH — the pipeline operator pattern is idiomatic Elixir. Sources: [Elixir Pipeline Pattern](https://mattpruitt.com/articles/the-pipeline/)

---

### Component 7: Team (`PhoenixAI.Team`)

Single responsibility: run multiple agents in parallel and merge their results. Uses `Task.async_stream` or `Task.Supervisor.async_stream` for parallel execution with fault isolation.

```elixir
defmodule PhoenixAI.Team do
  def run(agent_specs, merge_fn, opts \\ []) do
    max_concurrency = Keyword.get(opts, :max_concurrency, length(agent_specs))

    agent_specs
    |> Task.async_stream(
      fn {provider, prompt, agent_opts} ->
        {:ok, pid} = Agent.start_link(agent_opts)
        Agent.prompt(pid, prompt)
      end,
      max_concurrency: max_concurrency,
      timeout: Keyword.get(opts, :timeout, 60_000)
    )
    |> Enum.reduce({:ok, []}, fn
      {:ok, {:ok, result}}, {:ok, acc} -> {:ok, [result | acc]}
      {:ok, {:error, _} = err}, _ -> err
      {:exit, reason}, _ -> {:error, {:task_failed, reason}}
    end)
    |> then(fn {:ok, results} -> merge_fn.(Enum.reverse(results)) end)
  end
end
```

**Communicates with:** Agent runtime (spawns agents), public API caller (returns merged results)

**Confidence:** HIGH — `Task.async_stream` is well-documented standard OTP. Sources: [Elixir Task.Supervisor docs](https://hexdocs.pm/elixir/Task.Supervisor.html)

---

### Component 8: Structured Output (`PhoenixAI.Schema`)

Single responsibility: define JSON schemas for LLM responses and validate/cast the returned JSON into Elixir maps or Ecto-compatible structs.

Two approach options (pick one):
1. **Ecto changesets** — familiar to Phoenix developers, built-in to the ecosystem (used by Instructor.ex and Mojentic)
2. **Plain maps + NimbleOptions** — lighter dependency for non-Phoenix apps

Recommendation: Ecto changesets via an optional `instructor_ex` integration, with fallback to plain map validation so the library is not Phoenix/Ecto-dependent.

**Communicates with:** Provider adapter (sends schema to format_tools/structured_output params), Agent runtime (validates response before returning to caller)

**Confidence:** MEDIUM — Instructor.ex and Mojentic validate the Ecto approach, but the optional integration pattern needs design work. Sources: [Instructor.ex](https://github.com/thmsmlr/instructor_ex), [Mojentic](https://hexdocs.pm/mojentic/structured_output.html)

---

## Data Flow

### Flow 1: Simple Chat Request

```
Caller
  → PhoenixAI.chat(messages, provider: :openai, model: "gpt-4o")
    → resolve provider module from config
    → PhoenixAI.Providers.OpenAI.chat(canonical_messages, opts)
      → serialize messages to OpenAI format
      → Req.post!(openai_url, body: openai_payload, headers: auth_headers)
      → parse HTTP response
      → return {:ok, %Response{...}}
    ← {:ok, %Response{content: "...", usage: %{...}}}
  ← {:ok, %Response{...}}
```

### Flow 2: Agent with Tool Calling Loop

```
Caller
  → PhoenixAI.Agent.prompt(pid, "What is the weather in Lisbon?")
    → Agent GenServer appends user message to conversation state
    → Provider.chat(conversation.messages, tools: formatted_tools)
    ← %Response{finish_reason: "tool_use", tool_calls: [%ToolCall{name: "get_weather", args: %{city: "Lisbon"}}]}
    → Agent dispatches: WeatherTool.execute(%{city: "Lisbon"}, context)
    ← {:ok, "15°C, sunny"}
    → Agent appends ToolResult to conversation
    → Provider.chat(conversation.messages)  ← second pass, tool result now in history
    ← %Response{finish_reason: "stop", content: "The weather in Lisbon is 15°C and sunny."}
  ← {:ok, %Response{content: "The weather in Lisbon is 15°C and sunny."}}
```

### Flow 3: Streaming Response

```
Caller
  → PhoenixAI.stream(messages, on_chunk: fn chunk -> send(caller_pid, {:chunk, chunk}) end)
    → PhoenixAI.Providers.Anthropic.stream(messages, on_chunk, opts)
      → PhoenixAI.HTTP.Stream.stream(anthropic_sse_url, headers, body, raw_on_chunk)
        → Finch opens persistent HTTP connection
        → Finch.stream callback fires on each SSE line
        → parse_chunk/1 called per line → %StreamChunk{}
        → on_chunk.(%StreamChunk{delta: "The "})
        → on_chunk.(%StreamChunk{delta: "weather"})
        → ... until %StreamChunk{finish_reason: "stop"}
    ← {:ok, %Response{content: aggregated_content, usage: %{...}}}
  ← {:ok, %Response{...}}
```

### Flow 4: Parallel Agent Team

```
Caller
  → PhoenixAI.Team.run([
      {provider: :openai, prompt: "Write the intro"},
      {provider: :anthropic, prompt: "Write the body"},
      {provider: :openai, prompt: "Write the conclusion"}
    ], merge_fn: &String.join(&1, "\n\n"))
    → Task.async_stream spawns 3 concurrent agent processes
    → Each agent independently calls its provider
    → Results collected as tasks complete
    → merge_fn called with [intro, body, conclusion]
  ← {:ok, "intro\n\nbody\n\nconclusion"}
```

### Flow 5: Sequential Pipeline

```
Caller
  → PhoenixAI.Pipeline.run([
      &search_web/1,
      &write_summary/1,
      &generate_social_posts/1
    ], initial_query)
    → step 1: search_web(initial_query) → {:ok, web_results}
    → step 2: write_summary(web_results) → {:ok, summary}
    → step 3: generate_social_posts(summary) → {:ok, posts}
  ← {:ok, posts}
```

---

## OTP Process Map

```
Application Supervision Tree (library consumer's app)
└── PhoenixAI.Supervisor (optional, started by library or consumer)
    ├── PhoenixAI.Finch (Finch HTTP pool for streaming)
    ├── DynamicSupervisor (for named agent sessions)
    │   ├── PhoenixAI.Agent [session_1]  (GenServer)
    │   ├── PhoenixAI.Agent [session_2]  (GenServer)
    │   └── ...
    └── Task.Supervisor (for Team parallel execution)
        ├── Task [agent_spec_1]
        ├── Task [agent_spec_2]
        └── ...
```

**Restart strategy:** DynamicSupervisor uses one_for_one. Agent crashes do not affect other agents. Task failures in Team are caught and mapped to `{:error, {:task_failed, reason}}`.

---

## Patterns to Follow

### Pattern 1: Behaviour-Based Provider Abstraction

Use `@behaviour` and `@callback` to define provider contracts. Consumers select providers via config or runtime options. This enables test mocking without additional mock libraries.

```elixir
# In config/config.exs
config :phoenix_ai, :default_provider, PhoenixAI.Providers.OpenAI

# In tests
config :phoenix_ai, :default_provider, PhoenixAI.Providers.Mock
```

Source: [Swoosh adapter pattern](https://www.djm.org.uk/posts/writing-extensible-elixir-with-behaviours-adapters-pluggable-backends/)

### Pattern 2: Railway-Oriented Pipelines

All public functions return `{:ok, result}` or `{:error, reason}`. Never raise in the library core. Use `with` for multi-step operations:

```elixir
def prompt(agent_pid, text, opts \\ []) do
  with {:ok, _} <- validate_prompt(text),
       {:ok, response} <- GenServer.call(agent_pid, {:prompt, text, opts}, timeout(opts)) do
    {:ok, response}
  end
end
```

### Pattern 3: Spawn Tasks Inside Agent, Handle with handle_info

When an agent makes an async provider call (e.g., for streaming), spawn a `Task` linked to the GenServer. The BEAM automatically delivers the result to `handle_info/2`:

```elixir
def handle_call({:prompt, text, opts}, from, state) do
  task = Task.async(fn -> Provider.chat(state.messages, opts) end)
  {:noreply, %{state | pending: {task, from}}}
end

def handle_info({ref, result}, %{pending: {%Task{ref: ref}, from}} = state) do
  GenServer.reply(from, result)
  {:noreply, %{state | pending: nil}}
end
```

Source: [Elixir Forum Task inside GenServer](https://elixirforum.com/t/test-for-async-task-inside-a-genserver/29426)

### Pattern 4: NimbleOptions for Configuration Schemas

Use NimbleOptions to validate all public function options at compile time where possible. This provides self-documenting schemas and clear error messages:

```elixir
@chat_schema NimbleOptions.new!([
  provider: [type: :atom, required: false],
  model: [type: :string, required: false],
  temperature: [type: :float, default: 1.0],
  max_tokens: [type: :pos_integer],
  tools: [type: {:list, :atom}, default: []]
])
```

Source: [NimbleOptions docs](https://hexdocs.pm/nimble_options/NimbleOptions.html)

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: Provider Logic Leaking Into Agent Runtime

**What goes wrong:** The Agent GenServer contains `if provider == :openai do` conditionals.
**Why bad:** Breaks the behaviour contract; adding a provider requires modifying the agent core.
**Instead:** All provider-specific logic lives in the provider adapter module. The agent calls `provider.chat/2` without knowing which provider it is.

### Anti-Pattern 2: Using Req for SSE Streaming

**What goes wrong:** Req's plugin architecture does not support long-running SSE connections; requests hang or buffer the full response.
**Why bad:** Streaming doesn't work; memory spikes on large responses.
**Instead:** Use Finch directly for all streaming connections. This is validated by ReqLLM 1.0's production decision. Source: [ReqLLM blog](https://jido.run/blog/announcing-req_llm-1_0)

### Anti-Pattern 3: Storing Conversation History Outside the Agent

**What goes wrong:** The caller tracks message history as a list and passes it in on every request.
**Why bad:** Callers must know the internal shape of messages; history gets out of sync across processes.
**Instead:** The Agent GenServer owns the conversation state. Callers send prompts and receive responses. History retrieval is via `Agent.get_history/1`.

### Anti-Pattern 4: One Global Finch Pool for All Streaming

**What goes wrong:** A single Finch pool becomes a bottleneck for many concurrent streaming sessions.
**Why bad:** High-volume scenarios degrade; connections queue.
**Instead:** Configure adequate pool size in `PhoenixAI.Finch` and document tuning. For very high concurrency, consumers can start their own Finch pools.

### Anti-Pattern 5: Synchronous Tool Execution Inside handle_call

**What goes wrong:** Tool execution (HTTP calls, database queries) blocks the agent's GenServer while inside `handle_call`.
**Why bad:** Agent process is blocked; no other messages can be processed; timeouts occur.
**Instead:** Convert to async using Task (see Pattern 3 above). Execute tools in a Task, handle results in `handle_info`.

---

## Suggested Build Order

This order respects dependency direction — each component can be built and tested in isolation before the next layer depends on it.

```
Phase 1 — Core Foundation
  1a. Core Data Model structs (Message, Response, ToolCall, ToolResult, StreamChunk)
  1b. Provider Behaviour definition (@callback contracts only)
  1c. HTTP Transport layer (Req wrapper + Finch SSE layer)
  1d. First Provider Adapter (OpenAI — most common, best reference)

Phase 2 — Agent Fundamentals
  2a. Tool Behaviour definition
  2b. Agent GenServer (completion loop, no tools yet)
  2c. Add tool dispatch loop to Agent
  2d. Remaining Provider Adapters (Anthropic, OpenRouter)

Phase 3 — Structured Output
  3a. Schema definition (map-based, no Ecto dependency)
  3b. Provider-side structured output params (format_schema per provider)
  3c. Response validation/casting

Phase 4 — Streaming
  4a. Finch SSE streaming in HTTP transport layer
  4b. Provider streaming adapters (parse_chunk callbacks)
  4c. Agent streaming mode (stream chunks out via callback/PID)

Phase 5 — Orchestration
  5a. Pipeline (sequential, pure functions — no new OTP)
  5b. Team (parallel, Task.async_stream)
  5c. DynamicSupervisor integration for named sessions

Phase 6 — Developer Experience
  6a. NimbleOptions schemas for all public functions
  6b. Mock provider for testing
  6c. Telemetry events
```

**Rationale for this order:**
- Data model must exist before any adapter can be written (adapters output canonical structs)
- Provider behaviour must be defined before adapter OR agent (both depend on it)
- One provider working is sufficient to build and test the agent loop
- Streaming is separate from core chat flow; adding it later avoids premature complexity
- Orchestration (Pipeline, Team) composes over the agent, not under it — built last

---

## Scalability Considerations

| Concern | At 100 users | At 10K users | At 1M users |
|---------|--------------|--------------|-------------|
| Concurrent agents | DynamicSupervisor, one GenServer per session | Same — BEAM handles 10K processes natively | Distribute across nodes via :pg / distributed Erlang |
| Provider rate limits | Per-provider retry with exponential backoff in adapter | Add per-provider rate limiter process (GenServer token bucket) | Provider-specific pooling, multiple API keys |
| Streaming connections | Finch pool size 10 default | Tune Finch pool, monitor queue depth | Multiple Finch pools partitioned by provider |
| Memory (conversation history) | Bounded by model context window | Enforce max_messages config in Agent | Summarization tool to compress history |

---

## References

| Source | Confidence | Used For |
|--------|------------|----------|
| [ReqLLM overview](https://hexdocs.pm/req_llm/overview.html) | HIGH | Provider behaviour, streaming architecture |
| [ReqLLM 1.0 blog](https://jido.run/blog/announcing-req_llm-1_0) | HIGH | Finch-for-streaming decision |
| [Alloy Elixir Forum](https://elixirforum.com/t/alloy-a-minimal-otp-native-ai-agent-engine-for-elixir/74464) | HIGH | Minimal agent loop pattern, OTP integration |
| [Jido GitHub](https://github.com/agentjido/jido) | HIGH | Agent GenServer, directive pattern, multi-agent |
| [LangChain.ex HexDocs](https://hexdocs.pm/langchain/readme.html) | HIGH | LLMChain/ChatModel component hierarchy |
| [ex_llm GitHub](https://github.com/azmaveth/ex_llm) | HIGH | Provider delegation, pipeline patterns |
| [Laravel AI SDK docs](https://laravel.com/docs/12.x/ai-sdk) | HIGH | Agent interface, tool calling, structured output |
| [Fly.io streaming guide](https://fly.io/phoenix-files/streaming-openai-responses/) | HIGH | SSE parsing, Finch.stream/5 usage |
| [Swoosh adapter pattern](https://www.djm.org.uk/posts/writing-extensible-elixir-with-behaviours-adapters-pluggable-backends/) | HIGH | @behaviour/@callback for provider abstraction |
| [Elixir Task.Supervisor docs](https://hexdocs.pm/elixir/Task.Supervisor.html) | HIGH | Parallel agent execution pattern |
| [NimbleOptions docs](https://hexdocs.pm/nimble_options/NimbleOptions.html) | HIGH | Config schema validation |
| [Instructor.ex GitHub](https://github.com/thmsmlr/instructor_ex) | MEDIUM | Structured output with Ecto |
| [Mojentic structured output](https://hexdocs.pm/mojentic/structured_output.html) | MEDIUM | Ecto schema approach for LLM responses |
