# Technology Stack

**Project:** PhoenixAI — Elixir AI Integration Library
**Researched:** 2026-03-29
**Research Mode:** Ecosystem (Stack dimension)

---

## Recommended Stack

### Core HTTP Client

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| `req` | ~> 0.5.17 | HTTP requests to AI provider APIs | Industry standard in Elixir 2025; 11.3M+ downloads, 611 dependents. Built-in streaming via `into: :self` and `into: fun`. Sits atop Finch for connection pooling. Will become Phoenix default. Cleaner API than raw Finch or Tesla for this use case. |
| `finch` | ~> 0.17 (transitive via req) | Connection pooling | Pulled in by Req. No direct dependency needed unless low-level pool control is required. |

**Confidence:** HIGH — Verified on hex.pm (req v0.5.17, Jan 2026). Req is the explicit dependency of LangChain.ex, anthropix, instructor, and req_llm.

---

### JSON Encoding / Decoding

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| `jason` | ~> 1.4 | JSON encode/decode | Still the de facto standard across the ecosystem. Elixir 1.18 introduced `JSON` module (Dec 2024) with a Jason-compatible API, but ecosystem-wide adoption is early. Jason is the explicit dependency of every major AI library (req, instructor, anthropix, openai_ex). Use Jason for compatibility in a library context. |

**Confidence:** HIGH — Verified on hex.pm. Note: Elixir 1.18+ ships `JSON` as stdlib. A future refactor can make Jason an optional dep / swap to stdlib JSON once the ecosystem stabilises. For v1, Jason is the safe choice for broad compatibility.

**Do NOT use:** Poison (slower, outdated), Jaxon (only needed for streaming JSON incremental parsing — see streaming section below).

---

### Streaming (SSE Parsing)

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| `server_sent_events` | ~> 0.2 | Parse SSE frames from LLM streaming responses | Lightweight, spec-conformant, actively maintained. Used as a direct dependency by `req_llm`. Returns `{events, rest}` tuples making it easy to consume partial responses. |
| `req` async body | via `into: :self` or `into: fun` | Receive raw chunks from provider API | Req's built-in streaming sends chunks to caller process. Combine with `server_sent_events` to parse `data: {...}\n\n` frames. |

**Why not `req_sse`?** Smaller adoption, less battle-tested than `server_sent_events`. The latter is the dep chosen by `req_llm` (1.9.0, 6,900+ downloads/week).

**Streaming implementation pattern:**
```elixir
Req.get!(url,
  headers: headers,
  into: fn {:data, chunk}, {req, resp} ->
    {events, _rest} = ServerSentEvents.parse(chunk)
    Enum.each(events, &handle_event/1)
    {:cont, {req, resp}}
  end
)
```

**Confidence:** MEDIUM — `server_sent_events` library verified on hex.pm; pattern verified via req_llm source inspection and Fly.io blog posts.

---

### Structured Output / Schema Validation

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| `ecto` | ~> 3.12 | `embedded_schema` for request/response structs, changesets for validation | The standard Elixir data modelling and validation library. Works without a database. Used by instructor and LangChain.ex for exactly this purpose. Consumers already know Ecto. Provides cast, validate_required, validate_inclusion etc. for AI response validation. |
| `nimble_options` | ~> 1.1.1 | Validate library configuration options (provider config, model params, timeouts) | Dashbit's standard for library option validation. Used by anthropix and req_llm. Generates documentation automatically. NOT for AI response data — Ecto handles that. |

**Pattern:** Define `embedded_schema` for each provider's message/response shape. Use `Ecto.Changeset` to cast and validate AI responses for structured output. Export a `to_json_schema/1` helper that converts Ecto schema to OpenAI-compatible JSON schema for tool/function calling.

**Confidence:** HIGH — Ecto embedded schemas for AI structured output is established pattern used by `instructor` (v0.1.0, Feb 2025) and `mojentic`.

---

### Provider HTTP Adapters (Reference Implementations)

These are existing libraries to study and potentially wrap or draw from, NOT necessarily direct dependencies.

| Library | Version | Covers | Notes |
|---------|---------|--------|-------|
| `openai_ex` | ~> 0.9.20 | OpenAI API | Community-maintained, uses Finch directly. 310K+ downloads. Watch for Responses API support. |
| `anthropix` | ~> 0.6.2 | Anthropic (Claude) | Most featureful Anthropic client: tool use, extended thinking, prompt caching, streaming, message batching. Uses Req. 212K+ downloads. |
| `req_llm` | ~> 1.9.0 | 45+ providers via unified interface | OpenAI, Anthropic, OpenRouter, Groq, Bedrock, etc. Vercel AI SDK-style API. Typed structs. Built-in streaming. Apache-2.0. The closest prior art to PhoenixAI's goals. Evaluate as a possible foundation. |

**Decision:** PhoenixAI should implement its own thin provider adapters (not wrap these) to keep the dependency surface minimal and the API fully unified. Study `req_llm` architecture for OpenRouter provider model. Study `anthropix` for Anthropic streaming patterns.

**Confidence:** MEDIUM — All versions verified on hex.pm as of 2026-03-29.

---

### LangChain.ex — Reference Framework

| Library | Version | Role | Notes |
|---------|---------|------|-------|
| `langchain` | 0.6.3 (Mar 28 2026) | Closest existing ecosystem player | 555K+ all-time downloads, 14,962 downloads/week. Supports OpenAI, Anthropic, Google, Mistral, DeepSeek, Perplexity, Bedrock. Has tool calling, streaming, agent framework (v0.5+), multi-modal. Heavy dependency: pulls in Ecto, Req, optional Nx. |

**PhoenixAI vs LangChain.ex:**
- LangChain.ex is framework-oriented (opinionated chains, callbacks, Livebook demos). PhoenixAI targets a lighter, more composable library API closer to laravel/ai.
- LangChain.ex does NOT have first-class OTP agent supervision. PhoenixAI's BEAM-native parallel agent execution is a genuine differentiator.
- LangChain.ex's `ChatReqLLM` adapter (added v0.6.2) delegates to `req_llm` — validates that `req_llm` is production-grade.

**Do NOT depend on LangChain.ex.** Use as research and competitive reference only.

**Confidence:** HIGH — Verified changelog and downloads on hex.pm/hexdocs.

---

### Instructor.ex — Structured Output Reference

| Library | Version | Role |
|---------|---------|------|
| `instructor` | 0.1.0 (Feb 2025) | Structured output via Ecto for LLMs |

Instructor provides `Chat.complete(response_model: MyEctoSchema, ...)` which returns a validated Ecto struct. This is the canonical pattern for AI structured output in Elixir. PhoenixAI should implement equivalent functionality natively using the same Ecto embedded_schema convention so users aren't surprised.

**Do NOT depend on instructor** (it pins to specific OpenAI response shapes). Implement the pattern directly.

**Confidence:** HIGH — Verified on hex.pm.

---

### OTP Concurrency Layer

No external libraries needed — these are BEAM primitives.

| Primitive | Purpose | PhoenixAI Use |
|-----------|---------|---------------|
| `Task.async` / `Task.await_many` | Parallel provider calls, parallel agent execution | Run N agents concurrently, await all results |
| `Task.Supervisor` | Supervised parallel execution with fault isolation | Wrap agent task tree under caller-provided supervisor |
| `GenServer` | Long-running stateful agents with conversation history | `PhoenixAI.Agent` behaviour backed by GenServer |
| `Supervisor` / `DynamicSupervisor` | Fault-tolerant agent lifecycle | Consumer uses their app supervisor; PhoenixAI exposes `child_spec/1` |
| `Stream` | Lazy evaluation of streaming responses | Thread SSE chunks through Elixir Stream |

**Key decision:** PhoenixAI should ship a `PhoenixAI.Agent` behaviour that callers implement, plus a runtime GenServer wrapper. DO NOT bake in DynamicSupervisor — provide `child_spec/1` so callers integrate into their own supervision tree. This follows Elixir library guidelines.

**Confidence:** HIGH — Core BEAM/OTP, no versioning concern.

---

### Testing Infrastructure

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| ExUnit | stdlib | Unit and integration tests | Built into Elixir, no dep needed |
| `mox` | ~> 1.2 | Mock HTTP adapters and provider behaviours | Dashbit's official mock library. Requires Behaviour contracts — aligns perfectly with PhoenixAI's provider adapter pattern. Concurrent-safe. |
| `bypass` | ~> 2.1 | Spin up local HTTP server for integration tests | For end-to-end HTTP round-trip tests against mock provider endpoints. Validates request shapes and headers. |
| `ex_doc` | ~> 0.34 | Documentation generation | Standard Mix library documentation. Required for hex.pm publication. |

**Confidence:** HIGH — All established Elixir library testing patterns.

---

### Telemetry

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| `telemetry` | ~> 1.3 | Emit instrumentation events | The Elixir/Erlang standard for library instrumentation. Pulled in by Phoenix/Ecto automatically. Libraries MUST emit `:telemetry` events but MUST NOT depend on collection/reporting backends. Consumers wire up their own Prometheus/OpenTelemetry. |

**Events to emit (recommended):**
- `[:phoenix_ai, :request, :start]` — before provider HTTP call
- `[:phoenix_ai, :request, :stop]` — after response (includes duration, model, token counts)
- `[:phoenix_ai, :request, :exception]` — on error
- `[:phoenix_ai, :stream, :chunk]` — each SSE chunk received
- `[:phoenix_ai, :tool, :call]` — when a tool is invoked

**Confidence:** HIGH — Telemetry is the universal Elixir library instrumentation standard.

---

## Full Dependency List

### Runtime Dependencies

```elixir
defp deps do
  [
    {:req,                  "~> 0.5"},        # HTTP client (required)
    {:jason,                "~> 1.4"},        # JSON encode/decode (required)
    {:ecto,                 "~> 3.12"},       # Struct validation / embedded schemas (required)
    {:nimble_options,       "~> 1.1"},        # Library config option validation (required)
    {:server_sent_events,   "~> 0.2"},        # SSE frame parsing for streaming (required)
    {:telemetry,            "~> 1.3"},        # Instrumentation events (required)
  ]
end
```

### Dev / Test Dependencies

```elixir
defp deps do
  [
    # ... runtime deps above ...
    {:mox,     "~> 1.2",  only: :test},
    {:bypass,  "~> 2.1",  only: :test},
    {:ex_doc,  "~> 0.34", only: :dev, runtime: false},
    {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
    {:credo,   "~> 1.7",  only: [:dev, :test], runtime: false},
  ]
end
```

**Total runtime dep count: 6** — deliberately lean for a library. Consumers should not inherit a heavyweight framework as a transitive dep.

---

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| HTTP client | `req` | `tesla` | Tesla requires adapter configuration boilerplate; Req is simpler and has better defaults for API clients. 11.3M downloads vs Tesla's lower adoption. |
| HTTP client | `req` | `httpoison` | HTTPoison is older, less ergonomic, based on hackney. Req is the clear 2025 winner. |
| HTTP client | `req` | raw `finch` | Finch requires more boilerplate (pool naming, request building). Req wraps it cleanly. |
| JSON | `jason` | stdlib `JSON` (Elixir 1.18) | Stdlib JSON is newer (Dec 2024) — ecosystem adoption incomplete. Many Req and Ecto internals still depend on Jason. Use Jason for library compatibility; revisit in 2026. |
| Structured output | Custom Ecto pattern | `instructor` | Instructor couples to OpenAI response format. PhoenixAI needs provider-agnostic structured output. Implement the pattern directly. |
| SSE parsing | `server_sent_events` | `req_sse` | `server_sent_events` has higher adoption, used as dep by `req_llm`. |
| Validation | `nimble_options` | `norm` | NimbleOptions is Dashbit-maintained, generates docs automatically, standard for Mix library configs. Norm is more powerful but unnecessary here. |
| Agent framework | Native OTP | `jido` / `jido_ai` | Jido (2.0, HN-featured) is interesting but adds a heavy dependency. PhoenixAI's differentiator IS the OTP-native agent layer — outsourcing it defeats the purpose. |
| Mock testing | `mox` | `mock` | Mox requires Behaviour contracts, which enforces good architecture. `mock` allows mocking any module (bad for library design). |

---

## Elixir / OTP Version Requirements

| Requirement | Minimum | Recommended | Reason |
|-------------|---------|-------------|--------|
| Elixir | ~> 1.17 | 1.18+ | 1.17 required by LangChain 0.6.x (uses `get_in` macro). 1.18 adds native JSON module. |
| Erlang/OTP | 26+ | 27 | OTP 27 added native JSON in Erlang; OTP 26 for stable `proc_lib` improvements. |

**Declare in `mix.exs`:**
```elixir
def project do
  [
    elixir: "~> 1.17",
    ...
  ]
end
```

**Confidence:** HIGH — Verified against LangChain changelog and Elixir release notes.

---

## Sources

- [LangChain Elixir - hex.pm](https://hex.pm/packages/langchain) — v0.6.3, Mar 28 2026
- [LangChain Changelog](https://hexdocs.pm/langchain/changelog.html) — verified providers, tool calling, streaming
- [Req - hex.pm](https://hex.pm/packages/req) — v0.5.17, Jan 2026
- [instructor - hex.pm](https://hex.pm/packages/instructor) — v0.1.0, Feb 2025
- [anthropix - hex.pm](https://hex.pm/packages/anthropix) — v0.6.2, Jun 2025
- [openai_ex - hex.pm](https://hex.pm/packages/openai_ex) — v0.9.20, Mar 2026
- [req_llm - hex.pm](https://hex.pm/packages/req_llm) — v1.9.0, Mar 27 2026
- [server_sent_events - hex.pm](https://hex.pm/packages/server_sent_events)
- [nimble_options - hex.pm](https://hex.pm/packages/nimble_options) — v1.1.1
- [Elixir v1.18 release announcement](https://elixir-lang.org/blog/2024/12/19/elixir-v1-18-0-released/) — native JSON module
- [Req v0.5 released - Dashbit Blog](https://dashbit.co/blog/req-v0.5) — async streaming
- [Andrea Leopardi - HTTP Clients in Elixir](https://andrealeopardi.com/posts/breakdown-of-http-clients-in-elixir/) — Req/Finch recommendation
- [Streaming OpenAI responses - Fly.io Phoenix Files](https://fly.io/phoenix-files/streaming-openai-responses/) — SSE streaming pattern
- [Mox - dashbitco/mox](https://github.com/dashbitco/mox) — mock testing
- [Jido Agent Framework](https://hexdocs.pm/jido/readme.html) — alternative considered
