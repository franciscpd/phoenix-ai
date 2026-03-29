# Domain Pitfalls

**Domain:** Elixir AI provider abstraction library (multi-provider, streaming, tool calling, OTP agents)
**Researched:** 2026-03-29
**Overall confidence:** HIGH (OTP/process pitfalls), MEDIUM (provider-specific normalization)

---

## Critical Pitfalls

Mistakes that cause rewrites or fundamentally broken behavior.

---

### Pitfall 1: Leaky Provider Abstraction — Over-Normalizing What Can't Be Normalized

**What goes wrong:** The abstraction tries to flatten all provider differences into a single shared struct, hiding capabilities that only one provider supports (e.g., Anthropic's `thinking` blocks, OpenAI's `parallel_tool_calls`, provider-specific vision formats). When a consumer needs that provider-specific feature, the abstraction either silently drops it or requires breaking out of the abstraction entirely — forcing a rewrite at exactly the wrong time.

**Why it happens:** Developers model the abstraction around the intersection of all providers rather than the union. They test only with one provider (usually OpenAI) and discover the gaps when Anthropic behaves differently.

**Consequences:** Consumers discover the abstraction is useless for their real use case. They bypass it, the abstraction adds no value, and eventually gets removed or forked. The LangChain Python ecosystem hit this exact wall — "works well for POC but fails when you need custom behaviour or anything beyond OpenAI."

**Prevention:**
- Model the abstraction around a shared core (messages, role, content) with optional provider-specific escape hatches in each request/response struct.
- Every provider adapter must have its own integration test suite against real SSE responses (recorded fixtures).
- Design the internal message format to carry `provider_options: map()` passthrough for anything outside the core.
- Document explicitly what each provider supports and what falls through to passthrough.

**Warning signs:**
- "It works with OpenAI but not Anthropic" bug reports within first two weeks of multi-provider support.
- Growing list of special-case `if provider == :anthropic do` branches in shared code.

**Phase:** Provider abstraction foundation phase (Phase 1-2).

---

### Pitfall 2: Streaming SSE Chunk Fragmentation — Assuming One Event Per TCP Packet

**What goes wrong:** The HTTP client delivers chunks to the application, and naive implementations assume each chunk maps 1:1 to an SSE event. In reality, one TCP packet can carry multiple `data:` lines, and a single event can be split across two packets. Parsing without a stateful buffer causes malformed JSON decodes, missed events, and silent data loss.

**Why it happens:** The happy path (small responses over fast connections) works during development. The bug only appears under load, with long responses, or over slower connections.

**Consequences:** Partial tool call arguments get decoded as complete, causing JSON parse errors. Token counts are wrong. The `[DONE]` sentinel is missed. Stream-based UIs show corrupted or truncated output.

**Prevention:**
- Implement a stateful SSE parser that accumulates bytes until a `\n\n` boundary is found before attempting JSON decode.
- Never decode individual lines in isolation — always buffer and split on the event boundary.
- Write unit tests with synthetic fragmented chunks (split mid-event, multiple events in one chunk).
- Reference: OpenAI community thread confirms their streaming is "not strictly SSE-conformant" in places.

**Warning signs:**
- `Jason.decode!/1` crashes appearing in streaming logs.
- Intermittent "stream ended early" errors that don't reproduce locally.
- Tool call arguments arriving truncated.

**Phase:** Streaming implementation phase. Flag for deep research before writing SSE parser.

---

### Pitfall 3: GenServer as a Streaming Bottleneck

**What goes wrong:** A single GenServer is put in charge of managing a streaming response (buffering chunks, accumulating the result, forwarding to callers). Since GenServers process one message at a time, concurrent streaming requests queue behind each other. A 10-second streaming response blocks all other messages to that GenServer for its entire duration.

**Why it happens:** GenServer feels natural for stateful accumulation. Developers reach for it without considering that each streaming session is independent and shouldn't share a serialization point.

**Consequences:** Throughput collapses under concurrent load. The 5-second default timeout triggers under load while the GenServer is busy with another stream. Setting `:infinity` creates an unbounded mailbox that can crash the VM.

**Prevention:**
- Spawn a dedicated `Task` (or lightweight process) per streaming session, not a shared GenServer.
- Use `Task.Supervisor.async_nolink/3` for supervised but unlinked stream tasks.
- The accumulation state belongs to the per-request process, not a shared singleton.
- Use `GenServer` only for shared mutable state with a lifetime longer than a single request (e.g., connection pool, rate limiter token bucket).

**Warning signs:**
- A module named `StreamManager` or `ResponseBuffer` that is a singleton GenServer.
- Latency increasing linearly with concurrent requests.
- `:timeout` errors appearing in logs when multiple streams run simultaneously.

**Phase:** Streaming implementation phase.

---

### Pitfall 4: Wrapping OTP in a "Framework Layer" That Fights the Platform

**What goes wrong:** Inspired by Python/JavaScript agent frameworks, the library introduces its own `Agent` abstraction, lifecycle hooks, and orchestration primitives that duplicate what OTP supervisors, `GenServer`, and `Task.Supervisor` already provide — but without the battle-tested fault tolerance. The wrapper hides the supervision tree, making it impossible to integrate with the host application's supervision strategy or observe in LiveDashboard.

**Why it happens:** The author ports mental models from non-BEAM languages. The blog post "Why Elixir/OTP doesn't need an Agent framework" explicitly calls this out: frameworks that wrap OTP end up with more abstraction, worse performance at scale, and less transparency when things go wrong.

**Consequences:** Consumers cannot customize restart strategies. Crashes propagate unexpectedly. The library is incompatible with host apps that have their own supervision trees. Telemetry and observability tools cannot see inside the opaque wrapper.

**Prevention:**
- Expose OTP primitives directly. Parallel agents should be `Task.Supervisor.async_stream/5` calls, not a custom `Orchestrator` GenServer.
- The library's supervision tree (Finch pool, rate limiter) should be minimal and documented so consumers can integrate it.
- Provide a `child_spec/1` for optional supervised components; never start processes that the consumer didn't explicitly add to their tree.
- Let consumers choose supervision strategies (`restart: :temporary` vs `:permanent`) for long-lived agents.

**Warning signs:**
- A `PhoenixAI.Supervisor` that auto-starts in the Application callback without consumer opt-in.
- Custom `Agent` structs that wrap GenServer state in ways that prevent OTP introspection.
- `start_link` calls happening inside library functions rather than inside the consumer's supervision tree.

**Phase:** OTP agent architecture phase and library initialization design.

---

### Pitfall 5: Tool Call Result Injection — Wrong Message Role Breaks Conversation

**What goes wrong:** After a model returns a tool call, the library injects the tool result back into the conversation with the wrong role or in the wrong position. OpenAI requires tool results as `role: "tool"` messages with a matching `tool_call_id`. Anthropic requires them as `role: "user"` messages with a `type: "tool_result"` content block. Mixing these formats causes the provider to refuse the request or silently ignore the tool result.

**Why it happens:** The unified message format abstracts roles, but tool result injection is provider-specific and easy to get wrong when testing only against one provider.

**Consequences:** The model never "sees" the tool result and either loops (calling the same tool repeatedly) or produces a response that ignores the tool execution entirely.

**Prevention:**
- Tool result injection must be handled by the provider adapter, not by shared pipeline code.
- Write a dedicated test for the round-trip: model requests tool → library calls tool → result injected → model continues.
- Test this against both OpenAI and Anthropic fixtures before shipping tool calling.
- The `tool_call_id` correlation (OpenAI) must be preserved through the pipeline — never discard it.

**Warning signs:**
- "Invalid tool result" or "unexpected message role" API errors.
- Model generates a response that ignores a tool that was just called.
- Tool calls working in single-provider tests but failing in multi-provider integration tests.

**Phase:** Tool calling implementation phase.

---

## Moderate Pitfalls

---

### Pitfall 6: Application Environment as Configuration API

**What goes wrong:** The library uses `Application.get_env(:phoenix_ai, :openai_api_key)` as its primary configuration mechanism. This is global, process-unaware, and untestable. Tests that set different API keys per test process collide. Consumers running multiple provider configurations in the same app (e.g., two different OpenAI organizations) cannot do it.

**Prevention:**
- Accept configuration at the call site: `PhoenixAI.chat(messages, provider: :openai, api_key: key)`.
- Use Application env only as the default fallback, never as the only path.
- Follow the pattern used by Req: options at call site, defaults from config, no global mutable state.
- Official Elixir library guidelines explicitly warn: "avoid global configuration — it is best reserved for boot-time, application-level settings."

**Warning signs:**
- Tests that need `:application.set_env` in setup blocks.
- No way to pass a different API key per request.

**Phase:** Core API design phase.

---

### Pitfall 7: Supervision Tree Pollution — Starting Processes Without Consumer Consent

**What goes wrong:** The library defines `use Application` and starts a supervision tree automatically when loaded, adding Finch pools, rate limiters, and registries to the consumer's application without their knowledge.

**Prevention:**
- Libraries must NOT define `use Application` unless they are standalone applications.
- Provide a `PhoenixAI.child_spec/1` that consumers explicitly add to their supervision tree.
- Document exactly what processes are started and what resources they consume.
- Make the Finch pool name configurable so consumers who already use Finch don't get a duplicate pool.

**Warning signs:**
- `def start(_type, _args)` in the library's main module.
- Processes appearing in the consumer's supervision tree that the consumer didn't add.

**Phase:** Library initialization and supervision design.

---

### Pitfall 8: Context Window Blindness — Unbounded Conversation History

**What goes wrong:** The library accumulates conversation history indefinitely. A long-running agent or multi-turn conversation eventually exceeds the model's context window, causing a hard API error. The error message from the provider is cryptic, and the consumer doesn't know why it happened.

**Prevention:**
- Expose token count estimates (or character count as a proxy) on the conversation struct.
- Do not silently truncate — raise or return `{:error, :context_exceeded}` so consumers can handle it.
- Document the responsibility boundary clearly: the library provides the mechanism; the consumer decides the truncation strategy (last-N messages, summarize, sliding window).
- Consider providing optional helpers for common strategies (keep-last-N, discard-system-excluded) without forcing them.

**Warning signs:**
- No `length` or `token_estimate` field on the message list.
- Integration tests that only use short conversations.

**Phase:** Conversation management phase.

---

### Pitfall 9: No Backpressure on Parallel Agent Execution

**What goes wrong:** `Task.async_stream` (or raw `Task.async`) is used to launch parallel agents with no concurrency limit. When a consumer runs 50 parallel agents, the library spawns 50 concurrent HTTP requests to the provider. Most providers rate-limit at 60 RPM. All 50 requests hit simultaneously, 47 fail with 429, and the consumer gets a confusing error with no retry logic.

**Prevention:**
- `Task.async_stream` has a `max_concurrency` option — expose it.
- Default `max_concurrency` to a conservative value (e.g., 5) with documentation explaining why.
- Implement 429 detection and exponential backoff with jitter at the HTTP adapter layer.
- Log rate limit hits as warnings with the provider-specific `Retry-After` header value.

**Warning signs:**
- No `max_concurrency` option in the parallel agent API.
- No 429 handling in the HTTP client layer.
- Tests that spawn N agents but never simulate rate limit responses.

**Phase:** Parallel agent implementation phase.

---

### Pitfall 10: Behaviour vs. Protocol Misuse for Provider Polymorphism

**What goes wrong:** The provider abstraction is implemented using Elixir Protocols (dispatching on data type) instead of Behaviours (dispatching on module). Protocols are designed for data-type polymorphism (e.g., `Enumerable`, `Jason.Encoder`). Provider dispatch is module polymorphism ("which module handles `:openai`?"), which is exactly what Behaviours are for.

**Prevention:**
- Use `@behaviour PhoenixAI.Provider` for provider adapters — this is the correct OTP-idiomatic pattern.
- The provider behaviour defines the contract: `chat/2`, `stream/2`, `models/1`, etc.
- Each provider module (`PhoenixAI.Providers.OpenAI`) implements the behaviour and is selected at runtime via `provider: :openai` option resolution.
- Mox works natively with Behaviours, enabling clean test isolation without HTTP calls.

**Warning signs:**
- `defprotocol PhoenixAI.Provider do` in the codebase.
- Provider selection happening via `defimpl` blocks on structs.

**Phase:** Provider abstraction design phase.

---

### Pitfall 11: Streaming and Tool Calls Used Together Without Provider-Specific Handling

**What goes wrong:** When streaming is enabled alongside tool calling, providers behave very differently. A known LiteLLM bug (PR #12463) documents that Anthropic streaming + `response_format` + tools causes all tool calls to be incorrectly converted to content chunks. OpenAI streams partial tool call arguments incrementally, requiring index-based aggregation across chunks. These edge cases are invisible when only one mode is tested.

**Prevention:**
- Test streaming + tool calling as a combined scenario, not separately.
- Build a fixture library of real recorded streaming responses that include mid-stream tool calls for both OpenAI and Anthropic.
- Handle the Anthropic "content comes before tool call in stream" pattern explicitly.
- Track whether streaming + tools combination is explicitly tested in the CI matrix.

**Warning signs:**
- Tool calling tests use non-streaming mode only.
- No test fixture containing a streaming response with a `tool_use` event mid-stream.

**Phase:** Streaming + tool calling integration phase.

---

## Minor Pitfalls

---

### Pitfall 12: Overly Strict Version Pinning in mix.exs

**What goes wrong:** The library pins dependencies with `~> 1.2.3` (patch-level) instead of `~> 1.2` (minor-level). Consumers who also depend on those libraries get version conflicts that prevent compilation.

**Prevention:**
- Use `~> major.minor` not `~> major.minor.patch` in published library deps.
- To require a specific bug fix: `~> 1.2 and >= 1.2.3`.
- Test the library against the full semver range it declares compatible.

**Phase:** Library packaging and release.

---

### Pitfall 13: Blocking the Caller on GenServer.call During Long Streaming Responses

**What goes wrong:** A `GenServer.call/3` with default 5-second timeout is used to initiate a streaming request. The GenServer processes the HTTP request synchronously in `handle_call`. The call times out before the first token arrives, especially on slow model responses or large prompts.

**Prevention:**
- Never initiate HTTP calls inside `handle_call` for streaming operations.
- Use `handle_call` to register the caller PID, then spawn a Task that sends chunks back via `send/2` to the caller.
- Or use `GenServer.reply/2` early and continue asynchronously.
- Prefer the Task-per-request pattern over routing streaming through a GenServer at all.

**Phase:** Streaming implementation phase.

---

### Pitfall 14: Sending Large Message History Through Process Boundaries

**What goes wrong:** Entire conversation structs (potentially megabytes of accumulated history) are passed as arguments to spawned Tasks or sent as GenServer messages. Each message crossing a process boundary is deep-copied in the BEAM's heap. For long conversations, this creates GC pressure and latency spikes.

**Prevention:**
- Pass only what the Task needs — the message list and provider config, not the full context struct.
- If conversation state must be shared, use ETS for read-heavy access patterns rather than message passing.
- The Elixir anti-patterns docs explicitly flag "sending unnecessary data" across process boundaries.

**Phase:** Parallel agent implementation phase.

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|----------------|------------|
| Provider behaviour design | Using Protocol instead of Behaviour for provider dispatch | Use `@behaviour` + Mox for test isolation |
| Core HTTP client setup | Finch pool started without consumer opt-in | Expose `child_spec/1`, document required supervision |
| Streaming parser | Chunk fragmentation — naive line-by-line parsing | Stateful buffer with `\n\n` boundary detection |
| Streaming + tools | Provider format divergence in streamed tool calls | Build combined streaming+tool fixture tests for both providers |
| Tool call injection | Wrong role/format for tool results breaks conversation | Provider adapter handles injection, not shared pipeline |
| Parallel agents | No concurrency limit causes rate limit cascade | `max_concurrency` default + 429 backoff with jitter |
| Conversation management | Unbounded history causes context window errors | Expose token/length estimate, never silently truncate |
| OTP agent orchestration | Custom framework layer wraps and hides OTP | Use Task.Supervisor directly, expose child_spec not opaque wrappers |
| Library configuration | Application.get_env-only config blocks multi-tenancy and testing | Call-site options as primary, env as default fallback |
| Streaming GenServer | Single GenServer bottlenecks concurrent streams | Task-per-request, not shared singleton GenServer |

---

## Sources

- [Dangers of GenServers — Learn Elixir](https://learn-elixir.dev/blogs/dangers-of-genservers) — HIGH confidence
- [Process Anti-Patterns — Elixir v1.19.5 Docs](https://hexdocs.pm/elixir/process-anti-patterns.html) — HIGH confidence
- [Library Guidelines — Elixir v1.19.5](https://hexdocs.pm/elixir/library-guidelines.html) — HIGH confidence
- [Comparing streaming response structures across LLM APIs — Percolation Labs](https://medium.com/percolation-labs/comparing-the-streaming-response-structure-for-different-llm-apis-2b8645028b41) — MEDIUM confidence
- [Streaming OpenAI in Elixir Phoenix — Ben Reinhart](https://benreinhart.com/blog/openai-streaming-elixir-phoenix/) — MEDIUM confidence
- [Why Elixir/OTP doesn't need an Agent framework — goto-code.com](https://goto-code.com/why-elixir-otp-doesnt-need-agent-framework-part-1/) — MEDIUM confidence (404 at time of fetch, referenced in multiple secondary sources)
- [LangChain Elixir README and limitations](https://github.com/brainlid/langchain) — MEDIUM confidence
- [Mocks and explicit contracts — Dashbit Blog](https://dashbit.co/blog/mocks-and-explicit-contracts) — HIGH confidence
- [Task.Supervisor — Elixir v1.19.5](https://hexdocs.pm/elixir/Task.Supervisor.html) — HIGH confidence
- [Exponential Backoff with Elixir — Finiam Blog](https://blog.finiam.com/blog/exponential-backoff-with-elixir) — MEDIUM confidence
- [Assistants Streaming SSE non-conformance — OpenAI Developer Community](https://community.openai.com/t/assistants-streaming-not-conformant-with-sse-spec/760209) — MEDIUM confidence
- [LiteLLM streaming + tools bug fix (PR #12463)](https://github.com/BerriAI/litellm/pull/12463) — MEDIUM confidence
- [Stop using Behaviour to define interfaces, use Protocol — Yiming Chen](https://yiming.dev/blog/2021/07/18/stop-using-behaviour-to-define-interfaces-use-protocol/) — MEDIUM confidence (context: the inverse of this advice applies to provider dispatch)
