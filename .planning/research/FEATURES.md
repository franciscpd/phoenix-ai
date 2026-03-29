# Feature Landscape

**Domain:** Elixir AI Integration Library (inspired by laravel/ai)
**Researched:** 2026-03-29
**Reference libraries surveyed:** laravel/ai, Vercel AI SDK v6, LangChain (Python), LangChain (Elixir), ExLLM, ReqLLM, InstructorLite, Jido, SwarmEx, openai_agents

---

## laravel/ai API Surface Reference

Understanding laravel/ai's design is essential because PhoenixAI aims for parity adapted to Elixir idioms. Key API patterns:

### Agent Contract System (PHP)
Agents are classes implementing composable interfaces:
- `Agent` — base, required
- `Conversational` — implements `messages()` for context
- `HasTools` — implements `tools()` returning tool list
- `HasStructuredOutput` — implements `schema(JsonSchema)` for typed responses

### Inline vs Class Agents
```php
// Class agent (reusable, testable)
$response = (new SalesCoach)->prompt("Analyze this...");

// Inline/anonymous agent (quick, one-off)
$response = agent(instructions: "You are a coach...")
    ->prompt("Analyze this...");
```

### Multi-Agent Patterns (from Anthropic's 5 patterns)
- **Prompt chaining**: `Pipeline::send()->through([fn, fn, fn])->thenReturn()`
- **Parallelization**: `Concurrency::run([fn, fn, fn])` → merge results
- **Routing**: classify with structured output, delegate to specialist agent
- **Orchestrator-workers**: agent with tools that are themselves agents
- **Evaluator-optimizer**: generate → evaluate (structured output) → loop until approved

### Conversation Persistence
- `RemembersConversations` trait — auto-persist to `agent_conversations` table
- `->forUser($user)` → start new conversation
- `->continue($conversationId, as: $user)` → resume

---

## Table Stakes

Features users expect. Missing means the library feels incomplete or unusable as a foundation.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Multi-provider unified API | Every equivalent library has this; developers need provider flexibility | Medium | OpenAI, Anthropic, OpenRouter required at v1; pattern must allow extension |
| Synchronous text generation | Simplest use case; the "hello world" of the domain | Low | `{:ok, response} = AI.chat(provider, messages)` style |
| Streaming responses | Users expect real-time token output for chat UIs and long responses | Medium | SSE or chunked; must not block BEAM scheduler; Phoenix Channels integration natural target |
| Tool/skill calling | Core of "agent" behavior; all major frameworks expose this | High | Must translate Elixir functions to provider JSON schemas; handle tool result loop |
| Structured output | Typed, validated AI responses; essential for pipelines and reliability | Medium | JSON schema → provider request; response validation; retry on parse failure |
| Conversation history management | Stateful conversation required for assistants | Medium | Provider-agnostic message list; developer controls persistence |
| Configurable providers | API keys, model selection, per-call overrides | Low | Mix config + runtime override pattern |
| Error handling with tuples | Elixir convention; `{:ok, _}` / `{:error, _}` everywhere | Low | Never raise by default; provide bang variants |
| Provider-agnostic message format | Messages must be normalized across providers | Low | Role + content struct; convert to provider wire format |

---

## Differentiators

Features that set PhoenixAI apart from existing Elixir libraries (ExLLM, ReqLLM, LangChain Elixir) and make it the "laravel/ai of Elixir."

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Agent behaviour (Elixir behaviour/struct) | Single declarative module with instructions, tools, schema — mirrors laravel/ai class contract but Elixir-idiomatic | Medium | `use PhoenixAI.Agent` behaviour; callbacks: `instructions/0`, `tools/0`, `schema/0`, `on_message/1` |
| OTP-native parallel agents | `Task.async_stream` / `Task.Supervisor` for fan-out; Supervisors for fault-tolerant pipelines; native to BEAM — no bolted-on concurrency primitives | High | Equivalent to `Concurrency::run()` but idiomatic and supervised |
| Sequential pipeline DSL | Pipe-based pipeline (`|> then()`) for prompt-chaining workflows | Medium | `AI.Pipeline.run(payload, [&step_a/1, &step_b/1])` — composable, testable steps |
| Named agent processes (GenServer) | Long-running stateful agents as supervised GenServers with `via_tuple` naming | High | Enables persistent conversation context in process state; natural for chatbots and assistants |
| Test sandbox / mock provider | `PhoenixAI.TestProvider` that returns scripted responses; no network calls in tests | Medium | ExUnit-friendly; critical gap in current Elixir ecosystem per community discussion |
| Telemetry integration | `:telemetry` events for every AI call (start, stop, exception, token usage) | Low | Standard Elixir observability; plug into LiveDashboard or OpenTelemetry |
| Phoenix Channels / LiveView streaming | First-class helpers to push streaming tokens to LiveView assigns or Channel broadcasts | Medium | `stream_to_socket/3`, `stream_to_lv/3`; use Phoenix's existing PubSub |
| Provider failover | Automatic retry with fallback provider list | Medium | `providers: [:openai, :anthropic]` — try in order; matches laravel/ai's failover feature |
| Inline vs module agent | Both anonymous `AI.prompt("...", tools: [...])` and `use PhoenixAI.Agent` module patterns | Low | Matches laravel/ai's `agent()` helper vs class agent duality |

---

## Anti-Features

Features to explicitly NOT build in v1 (and likely ever for the core library).

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Built-in database persistence | Couples library to Ecto/Postgres; kills non-Phoenix adoption; laravel/ai does this but it's the wrong call for Elixir | Document a persistence callback protocol; let consumers implement with Ecto, ETS, Redis, or Mnesia |
| Web UI / LiveView components | Out of scope in PROJECT.md; not a UI library | Document integration patterns; let consumers own the UI |
| Embeddings / vector search | Separate concern per PROJECT.md; would balloon scope | Companion library later; recommend Pgvector/Qdrant integration separately |
| Image / audio generation | Multimodal out of scope for v1; adds provider complexity with low value for the core use cases | Leave for v2+ feature flag; focus on text agents first |
| Built-in RAG pipeline | Complex, domain-specific; ExEmbeddings or Pgvector ecosystem better placed | Document RAG as a use case pattern using the pipeline primitive |
| Provider-specific feature wrappers | Extended thinking, web search, prompt caching — provider-specific, unstable APIs | Allow pass-through of raw provider options; don't abstract leaky features |
| Python subprocess / Nx.Serving | Local model inference is a separate BEAM concern | Bumblebee ecosystem handles this; PhoenixAI targets hosted API providers |
| MCP server hosting | laravel/ai has Laravel MCP, but that's a separate product | Out of scope; MCP client support could be v2 tool source |
| Fine-tuning / training | Inference-only library | Not applicable |

---

## Feature Dependencies

Understanding build order — later features require earlier ones to be stable.

```
Provider adapter behaviour
  └── Unified message format (Message struct)
        ├── Synchronous chat (AI.chat/3)
        │     ├── Streaming (AI.stream/3)
        │     ├── Tool calling loop (requires chat + message format)
        │     │     └── Agent behaviour (requires tools + instructions + chat)
        │     │           ├── Sequential pipeline (requires agent as unit)
        │     │           └── Parallel agents (requires agent as unit + Task supervision)
        │     └── Structured output (requires chat + schema validation)
        │           └── Routing pattern (requires structured output + agent dispatch)
        └── Conversation history (requires message format)
              └── Named agent GenServer (requires conv. history + agent behaviour)

Cross-cutting (can be added at any layer):
  Telemetry → wraps any operation
  Test sandbox → mocks provider adapter
  Phoenix streaming helpers → wraps streaming + channel/socket
  Provider failover → wraps provider adapter call
```

---

## Ecosystem Gap Analysis

Comparing existing Elixir libraries against the laravel/ai feature surface:

| Feature | laravel/ai | ExLLM | ReqLLM | LangChain (Elixir) | Jido | PhoenixAI Target |
|---------|-----------|-------|--------|---------------------|------|-----------------|
| Multi-provider | Yes (10+) | Yes (13+) | Yes (18+) | Partial | No | Yes (3 at v1) |
| Streaming | Yes | Yes | Yes | Partial | No | Yes |
| Tool calling | Yes | Yes | Yes | Yes | Yes | Yes |
| Structured output | Yes | Via Instructor | Yes | Partial | No | Yes (built-in) |
| Agent behaviour/class | Yes (class) | No | No | Partial | Yes (GenServer) | Yes (behaviour) |
| Sequential pipeline DSL | Yes (Pipeline) | No | No | Chains | No | Yes |
| Parallel agents | Yes (Concurrency) | No | No | No | Partial | Yes (OTP-native) |
| Named agent (GenServer) | No (PHP) | No | No | No | Yes | Yes |
| Built-in persistence | Yes (Ecto) | No | No | No | No | No (by design) |
| Telemetry | Yes (events) | No | Partial | No | No | Yes |
| Test sandbox | Yes | No | No | No | No | Yes |
| Failover | Yes | No | No | No | No | Yes |
| Phoenix streaming helpers | N/A | No | No | No | No | Yes |

**Key insight:** No existing Elixir library combines the full laravel/ai feature surface (agents + tools + structured output + pipelines + parallelism) with Elixir/OTP idioms. The gap is real and the market exists.

---

## MVP Recommendation

**Prioritize (v1 — must ship together for usefulness):**

1. Provider adapter behaviour + OpenAI, Anthropic, OpenRouter implementations
2. Unified Message struct + normalization
3. Synchronous chat (`AI.chat/3`)
4. Tool/skill calling with automatic loop
5. Structured output via JSON schema
6. `use PhoenixAI.Agent` behaviour (instructions + tools + schema)
7. Streaming (`AI.stream/3`) + Phoenix helpers
8. Test sandbox provider
9. Telemetry events

**Second wave (v1.x — not blocking):**

10. Sequential pipeline DSL
11. Parallel agent execution helpers
12. Named agent GenServer + supervision
13. Provider failover
14. Conversation history protocol (callbacks, no persistence)
15. Inline/anonymous agent helper

**Defer:**
- Image/audio/embeddings: insufficient value for v1 core use cases
- MCP: v2
- RAG: companion library
- Built-in persistence: never (anti-feature)

---

## Sources

- [laravel/ai GitHub](https://github.com/laravel/ai) — MEDIUM confidence (fetched, v0.4.2 as of research date)
- [Laravel AI SDK Docs (12.x)](https://laravel.com/docs/12.x/ai-sdk) — HIGH confidence (official docs)
- [Building Multi-Agent Workflows with Laravel AI SDK](https://laravel.com/blog/building-multi-agent-workflows-with-the-laravel-ai-sdk) — HIGH confidence (official blog)
- [Vercel AI SDK Introduction](https://ai-sdk.dev/docs/introduction) — HIGH confidence (official docs, v6)
- [ExLLM Documentation](https://hexdocs.pm/ex_llm/ExLLM.html) — MEDIUM confidence (hexdocs, deprecated per README)
- [ReqLLM GitHub](https://github.com/agentjido/req_llm) — MEDIUM confidence (active library, fetched)
- [awesome-ml-gen-ai-elixir](https://github.com/georgeguimaraes/awesome-ml-gen-ai-elixir) — MEDIUM confidence (community-maintained)
- [Elixir Forum: Is anyone working on AI Agents in Elixir?](https://elixirforum.com/t/is-anyone-working-on-ai-agents-in-elixir/69989) — MEDIUM confidence (community discussion, current)
- [openai_agents for Elixir](https://hexdocs.pm/openai_agents/) — LOW confidence (v0.1.2, minimal docs available)
- [InstructorLite](https://github.com/martosaur/instructor_lite) — MEDIUM confidence (active, hexdocs)
- [Jido agent framework](https://github.com/agentjido/jido) — MEDIUM confidence (active, GitHub fetched)
