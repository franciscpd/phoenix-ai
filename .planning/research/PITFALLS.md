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

---

---

# Guardrails Milestone Pitfalls (v0.3.0)

**Domain:** Middleware-chain policy system added to existing Elixir AI library
**Researched:** 2026-04-04
**Confidence:** HIGH (Elixir behaviour/pipeline patterns), MEDIUM (jailbreak detection & security bypasses), HIGH (stateless/stateful boundary)

This section covers pitfalls specific to adding the v0.3.0 guardrails system to a library that already ships `chat/2`, `stream/2`, `Agent`, `Pipeline`, and `Team`.

---

## Critical Pitfalls

---

### Pitfall G1: Stateful Policy Logic Leaking Into the Stateless Core

**What goes wrong:** A policy module accumulates state across calls — tracking token usage, counting requests, maintaining a cost budget — and stores that state as process state or module-level ETS tables. This couples the stateless guardrails core to a process lifecycle and supervision tree. When `phoenix_ai_store` is meant to provide stateful policies, the stateless core becomes implicitly stateful, and the boundary no longer exists.

**Why it happens:** Token budget and cost limit policies feel like natural guardrails. The developer adds them directly in `phoenix_ai` without considering that `check/2` is called as a pure function with no persistent context between calls. A counter that increments per-call using a process dictionary or agent seems harmless in isolation.

**Consequences:**
- The stateless guarantee is broken — `phoenix_ai` now requires a running process to function.
- Tests that previously ran concurrently without coordination now collide on shared state.
- `phoenix_ai_store` cannot own the stateful policies cleanly because `phoenix_ai` has already defined half of them.
- Library consumers who do not use `phoenix_ai_store` get processes they didn't ask for.

**Prevention:**
- The `Policy.check/2` callback must be defined as a pure function: `(request, opts) -> {:ok, request} | {:halt, violation}`. No side effects, no state writes, no process lookups.
- Any policy that requires state (token budget, cost tracking, rate limiting) is explicitly out of scope for this milestone — documented in `PROJECT.md` under "Out of Scope."
- In tests, enforce this by running policy chains from multiple concurrent processes without coordination — if they collide, a policy has leaked state.
- Do not add `use GenServer` or `Agent` to any module in `PhoenixAI.Guardrails.*`.

**Warning signs:**
- A policy module with a `start_link/1` function.
- `Process.get/put` inside a `check/2` implementation.
- A test that requires `setup` to initialize a named process before the policy chain can run.
- `ETS.insert/2` calls inside any policy module.

**Phase to address:** Policy behaviour definition phase. Lock down the `check/2` typespec before any policy is implemented.

---

### Pitfall G2: Keyword-Based Jailbreak Detection with Uncontrolled False Positive Rate

**What goes wrong:** The `JailbreakDetector` ships with a static keyword list (e.g., "ignore previous instructions", "pretend you are", "jailbreak"). In production, legitimate prompts trigger these patterns: a developer asking how to "ignore previous instructions in a prompt template" to debug their pipeline, or a fiction writer prompting "pretend you are a detective." The false positive rate climbs, consumers disable the detector entirely, and the safety value is lost.

**Why it happens:** Keyword detection feels safe during development because the "obvious" attack phrases are all caught. The test suite uses only adversarial inputs — it never tests with the long tail of legitimate inputs that share vocabulary with attack prompts.

**Consequences:**
- Consumers who trust the default `:default` preset have legitimate use cases blocked.
- Consumers who find the false positives intolerable disable all jailbreak detection.
- A threshold parameter is added post-hoc, breaking the `check/2` signature or requiring a confusing options map.
- Security researchers can trivially bypass keyword matching with Unicode homoglyphs, zero-width characters, or token smuggling (inserting invisible characters between restricted characters). The detector provides false security.

**Prevention:**
- Document the known limitations upfront and prominently: keyword detection has high false positive rates and is bypassable via character substitution, Unicode obfuscation, and token smuggling. It is a first-pass heuristic, not a security guarantee.
- Ship with a configurable `threshold` from day one (number of matched patterns required to halt) — not added later.
- Ship with a configurable `scope` that controls which message roles are scanned (`:user_only`, `:all`). Scanning system prompts that the developer controls themselves is almost always a false positive source.
- Provide a `custom_patterns` option that allows consumers to replace the default list entirely.
- In tests, include false-positive regression cases: prompts that resemble attacks but are legitimate. Every keyword in the default list should have a corresponding legitimate-use test that passes.
- The `JailbreakDetector` behaviour exists precisely so consumers can swap in a real ML-based classifier without changing the policy chain. Design the default implementation as "safe fallback, not security guarantee."

**Warning signs:**
- Test suite contains only adversarial inputs, no legitimate inputs that use attack vocabulary.
- No `threshold` option in the `JailbreakDetection` policy config.
- No documented statement of limitations in module doc.
- Default keyword list grows past ~20 entries without a corresponding growth in false-positive test coverage.

**Phase to address:** JailbreakDetector implementation phase. Write false-positive test cases before writing the detector.

---

### Pitfall G3: Halt Semantics Ambiguity — "Halt" vs "Error" vs "Block"

**What goes wrong:** The policy chain is designed to halt on the first violation, but the return type of `check/2` blurs the distinction between "this request is blocked by policy" and "this policy check failed unexpectedly." Consumers receive `{:error, %PolicyViolation{}}` and cannot tell whether to log it as a security event (intentional block) or as an infrastructure failure (unexpected error). Telemetry events fire for both, polluting metrics dashboards.

**Why it happens:** Using `{:error, reason}` as the halt signal is the obvious Elixir convention from Railway-Oriented Programming. But `{:error, ...}` has a strong convention of "something went wrong unexpectedly." A policy halt is not an error — it is a successfully detected violation.

**Consequences:**
- Consumers' error monitoring tools (Sentry, AppSignal) alert on every policy violation as if it were a software bug.
- Telemetry handlers cannot distinguish policy violations from HTTP errors or runtime exceptions.
- The error log fills with "errors" that are actually normal, expected policy enforcements.
- Downstream code that pattern-matches `{:error, %PhoenixAI.Error{}}` versus `{:error, %PolicyViolation{}}` becomes brittle.

**Prevention:**
- Define the halt return as `{:halt, %PolicyViolation{}}` — not `{:error, ...}`. This is a distinct semantic: halt means "deliberately stopped," error means "something broke."
- The pipeline executor returns `{:halt, %PolicyViolation{}}` to the caller when any policy halts. The caller chooses how to treat it.
- Telemetry events for policy violations use a distinct event name: `[:phoenix_ai, :guardrails, :violation]`, separate from `[:phoenix_ai, :error]`.
- Document the contract clearly in the `Policy` behaviour module doc.

**Warning signs:**
- `check/2` callback spec returns `{:ok, request} | {:error, reason}` — missing the `:halt` tuple.
- Telemetry events for violations are emitted as `:error` status.
- Test helpers that match `assert {:error, _} = Guardrails.run(...)` for expected violations.

**Phase to address:** Policy behaviour definition — the typespec must be correct before any policy is implemented.

---

### Pitfall G4: Breaking the Existing API by Making Guardrails Mandatory

**What goes wrong:** The guardrails system is wired into `PhoenixAI.chat/2` and `PhoenixAI.stream/2` at the library level, so all calls go through the policy chain whether the consumer opted in or not. Consumers who do not configure any policies suddenly get an extra code path with latency overhead. The existing API's behavior changes — a breaking change that lands in a minor version.

**Why it happens:** "Defense in depth" thinking: guardrails should always run. The developer adds a `Guardrails.run(request, opts)` call at the top of `chat/2` without realizing that consumers who do not pass `:policies` will hit this path with an empty list every single call.

**Consequences:**
- Every existing test that calls `PhoenixAI.chat/2` must now be updated to pass `policies: []` or equivalent.
- Consumers who have not opted into guardrails see latency increase from the empty policy chain traversal.
- A breaking change is introduced in what should be a feature-addition release.
- Consumers who read the changelog see guardrails as something that "happened to them" rather than something they opted into.

**Prevention:**
- Guardrails are opt-in. The existing `chat/2`, `stream/2`, `Agent`, and `Pipeline` APIs are unchanged.
- Consumers who want guardrails call `PhoenixAI.Guardrails.run(request, policies: [...])` explicitly before their AI call, or wrap their own call site.
- The `Guardrails` module is a separate namespace — it does not patch existing modules.
- Existing tests must pass without modification after the guardrails milestone ships.

**Warning signs:**
- Any modification to `PhoenixAI.chat/2` or `PhoenixAI.stream/2` function signatures.
- `Guardrails.run/2` being called inside the existing provider adapter call path.
- Existing tests failing after the guardrails PR is merged.

**Phase to address:** Architecture design — decide the integration point before writing any code.

---

### Pitfall G5: ToolPolicy Denylist as a Security Guarantee (It Is Not)

**What goes wrong:** The `ToolPolicy` with a denylist is presented or documented as a security control. Consumers rely on it to prevent the model from using dangerous tools. An attacker or a misbehaving model prompt-injects around the denylist by using tools indirectly (e.g., chaining two "allowed" tools whose combined output has the same effect as the "denied" tool), or by generating a tool name that the denylist check misses due to case sensitivity or string normalization.

**Why it happens:** The denylist feels like an access control list. It is actually a first-pass filter on exact tool name strings. Researchers have shown that denylist-based controls are "always one step behind" attackers who find gaps (obfuscation via Base64, case variants, chained tool calls).

**Consequences:**
- A consumer ships with ToolPolicy denylist as their sole tool security control.
- An adversarial prompt routes around it via indirect tool chaining or name normalization.
- The consumer believes they are protected; they are not.
- When the bypass is discovered, the library takes reputational damage for "broken security."

**Prevention:**
- Document clearly: `ToolPolicy` is a convenience filter for developer-controlled scenarios (e.g., only allow specific tools per user role). It is not a security boundary against adversarial prompts.
- Prefer allowlist mode (`mode: :allow`) over denylist mode (`mode: :deny`) — an allowlist restricts to only what is explicitly permitted; a denylist can always be bypassed by finding a gap.
- Add a module doc warning: "Allowlist mode provides stronger guarantees than denylist mode. If security is critical, use allowlist mode and treat denylist mode as a convenience shortcut only."
- Normalize tool names before comparison (lowercase, trim whitespace) to prevent trivial bypasses.

**Warning signs:**
- Documentation that describes `ToolPolicy` as a "security control" without caveats.
- Tests only covering denylist mode, with no allowlist mode tests.
- No normalization of tool names in the comparison logic.

**Phase to address:** ToolPolicy implementation phase.

---

### Pitfall G6: ContentFilter with Mutable Closures Leaking State Between Requests

**What goes wrong:** The `ContentFilter` policy accepts user-provided pre/post functions. A consumer passes a function that captures a mutable reference (an Agent PID, a process dictionary write, or an ETS table write) intending to log or count filter invocations. When the same filter function is used across concurrent requests (which is valid), the captured mutable state becomes a concurrency hazard: double-counting, race conditions, or deadlock on the Agent.

**Why it happens:** The callback pattern (`fn message -> ...` / `fn response -> ...`) invites closures. A developer passing `fn msg -> Counter.increment() && :ok end` doesn't consider that the function is called from multiple concurrent processes.

**Consequences:**
- Incorrect counts in metrics derived from the filter callback.
- Deadlock when the captured Agent is a bottleneck under concurrent load.
- Non-deterministic test results when tests run concurrently.

**Prevention:**
- Document that filter functions must be pure or explicitly concurrent-safe.
- Do not store filter function state inside the library — the function is called as-is.
- In tests, run the filter chain from multiple concurrent tasks with the same filter function to validate it does not cause issues.
- The typespec for filter functions should signal pure intent: `(message :: term() -> {:ok, term()} | {:halt, PolicyViolation.t()})`.

**Warning signs:**
- Example code in module docs showing a filter function that writes to a process or ETS table.
- No concurrent-execution test for ContentFilter.

**Phase to address:** ContentFilter implementation phase.

---

## Moderate Pitfalls

---

### Pitfall G7: Policy Ordering Effects Are Not Documented or Tested

**What goes wrong:** The pipeline executor runs policies in the order provided. A consumer passes `[ContentFilter, JailbreakDetection, ToolPolicy]` and gets one behavior, but `[JailbreakDetection, ContentFilter, ToolPolicy]` gives a different result for the same input (because JailbreakDetection halts before ContentFilter even runs). The consumer is surprised by this — they expected the "strongest" policy to win, not the first one.

**Why it happens:** Halt-on-first-violation is a valid design (analogous to Plug.halt). But the ordering implications are not documented. Consumers assemble policies in intuitive order ("most important first") without knowing they are also defining precedence.

**Prevention:**
- Document explicitly: policies execute in definition order and halt on the first violation. Policy N+1 is never called if policy N halts.
- In tests, write test cases that exercise the same input against different orderings and assert expected outcomes for each.
- The `:default` preset must have a documented rationale for its ordering (e.g., "JailbreakDetection runs first because it is cheapest and catches the most common attacks").
- Consider emitting a telemetry event that includes the halting policy's position in the chain, so consumers can observe ordering effects in production.

**Warning signs:**
- Module doc for the pipeline executor does not mention ordering.
- No test that runs the same input through two differently-ordered policy chains.
- Preset ordering is defined without an inline comment explaining the rationale.

**Phase to address:** Pipeline executor implementation phase.

---

### Pitfall G8: The Request Struct Carrying Too Little Context for Policies to Be Useful

**What goes wrong:** The `Request` struct passed to `check/2` carries only the raw message list. A policy that needs to know the provider, the model, the calling user's role, or a request ID cannot make contextual decisions. `JailbreakDetection` with `scope: :user_only` cannot filter by role because there is no role in the struct. `ToolPolicy` cannot apply per-user allowlists. Consumer-defined policies are useless without access to business context.

**Why it happens:** The `Request` struct is modeled after the minimal "what goes to the provider" view. Guardrails need a richer "who is asking and in what context" view. These are different concerns that share a name.

**Prevention:**
- The `Request` struct must carry at minimum: `messages`, `provider`, `model`, `tools`, and a `metadata: map()` field for arbitrary consumer-provided context (user role, request ID, tenant ID).
- Policies access context through `request.metadata` — the library makes no assumptions about what is there.
- Document the `metadata` field as the extension point for business-context-aware policies.
- Write a test where `ToolPolicy` uses `request.metadata.user_role` to apply different allowlists — this validates the design works for the target use case.

**Warning signs:**
- `Request` struct has no `metadata` or `context` field.
- `ToolPolicy` allowlist is static (compile-time) with no way to vary it per-request.
- A consumer has to build a custom policy just to filter on provider or model.

**Phase to address:** Request struct definition phase — the struct must be complete before any policy is implemented.

---

### Pitfall G9: Preset Configurations That Cannot Be Extended Without Replacing Them

**What goes wrong:** The `:default`, `:strict`, and `:permissive` presets are implemented as hard-coded module lists. A consumer who wants `:strict` plus one custom policy must replace the entire preset. There is no "extend" mechanism — they copy the preset's policy list, add their policy, and maintain a fork of the preset forever.

**Why it happens:** Presets are the simplest implementation: a function returns a list of policy structs. Composition is not designed in.

**Prevention:**
- Presets return a list: `Guardrails.preset(:strict)` returns `[policy1, policy2, policy3]`.
- Since it is a list, consumers can append or prepend: `Guardrails.preset(:strict) ++ [MyPolicy.new()]`.
- Do not return opaque structs that cannot be pattern-matched or merged.
- Document the "extend a preset" pattern in the module doc with a code example.

**Warning signs:**
- `preset/1` returns an opaque struct rather than a list of policies.
- No documentation showing how to add a policy to an existing preset.

**Phase to address:** Preset implementation phase.

---

### Pitfall G10: Optional Callbacks in the Policy Behaviour Causing Silent No-Ops

**What goes wrong:** The `Policy` behaviour defines `check/2` as an `@optional_callback`. A consumer implements a policy module but misspells the callback (`def check(req, _opts)` instead of `def check(request, opts)` — same arity but different internal name is fine, but a wrong arity like `def check(req)` will not be warned by the compiler). The policy silently passes every request without checking anything.

**Why it happens:** Elixir's `@optional_callbacks` suppresses compiler warnings for unimplemented callbacks. This is the correct design for truly optional callbacks, but `check/2` is the entire purpose of the Policy behaviour — it should never be optional.

**Prevention:**
- `check/2` must be a required `@callback`, not an `@optional_callback`. The compiler will warn if a module declares `@behaviour PhoenixAI.Policy` but does not implement `check/2`.
- Write a compile-time test (using `Code.ensure_compiled!/1` in a test module that deliberately omits `check/2`) to verify the warning fires.
- In the behaviour doc, include a full working example of a minimal policy module so consumers have a reference to match against.

**Warning signs:**
- `@optional_callbacks [check: 2]` in the Policy behaviour module.
- No compile-time warning when a policy module omits `check/2`.
- Tests for custom policies that never verify the callback is actually invoked.

**Phase to address:** Policy behaviour definition phase.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Hardcoded keyword list in JailbreakDetector | Fast to ship, easy to understand | Grows uncontrollably, false positive rate rises, no testing regime | Never — ship with `custom_patterns` option from day one |
| Denylist-only ToolPolicy (skip allowlist) | Simpler implementation | Cannot provide security guarantees, consumers build false trust | Never for production — allowlist mode must ship with denylist |
| Static preset lists without extension mechanism | Simple to implement | Consumers fork presets, library loses control of quality | Only acceptable if documented with an explicit extension example |
| Embedding halt logic in each policy (not in executor) | Policies have more control | Ordering guarantees disappear, halt-on-first cannot be enforced | Never — halt is the executor's responsibility |
| Skipping `metadata` field on Request struct | Smaller struct surface area | Policies cannot make contextual decisions, consumers write wrapper layers | Only acceptable if documented as "v0.3.0 limitation, planned for v0.4.0" |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Existing `PhoenixAI.chat/2` | Wiring guardrails inside `chat/2` as mandatory | Keep `Guardrails.run/2` separate; consumer calls it before `chat/2` |
| `PhoenixAI.Pipeline` | Adding policy chain as a pipeline step | Pipeline steps transform data; guardrails halt execution — different semantics |
| `PhoenixAI.Agent` | Running guardrails inside `Agent.prompt/2` unconditionally | Accept `policies:` opt-in option in `Agent.start_link/1`; default to no policies |
| Telemetry integration | Emitting violations as `:error` status events | Use `[:phoenix_ai, :guardrails, :violation]` — distinct from error events |
| User-provided filter functions | Calling filter function inside a GenServer handle_call | Filter functions may block; call from outside GenServer context or from a Task |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Synchronous keyword scan on every token of a streaming response | Latency spike on long prompts, streaming slows to a crawl | Guardrails run on the full assembled request BEFORE the AI call, not per-token | Visible at prompts > 1000 tokens |
| Running all policies even after halt | CPU waste, misleading telemetry showing all policies ran | `Enum.reduce_while` with `:halt` — executor stops on first violation | Any size — correctness issue, not just scale |
| Regex compilation per-request in JailbreakDetector | Latency at >100 req/s | Compile patterns once at module load or config init; cache as module attribute | ~100 req/s sustained load |
| ContentFilter calling an external HTTP service (LLM-as-judge) synchronously | Doubles request latency, introduces new failure mode | Document that filter functions calling external services must handle timeouts and failures; recommend async where possible | Any synchronous call to slow external service |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Treating keyword-based JailbreakDetector as a security boundary | Unicode homoglyphs, zero-width characters, token smuggling trivially bypass keyword matching | Document limitations; design for easy swap-out to ML classifier via `JailbreakDetector` behaviour |
| Treating ToolPolicy denylist as access control | Indirect tool chaining, case variant tool names bypass denylist | Default to allowlist mode for security-sensitive use cases; document denylist limitations |
| PolicyViolation struct containing the original blocked message verbatim | Logging infrastructure may store and expose the attack payload | PolicyViolation carries violation type and policy name only — not the raw offending content by default |
| Exposing `check/2` results directly to end users | Error messages reveal the detection logic, aiding attackers | PolicyViolation reason is for developer logs; return generic user-facing error from the consumer layer |

---

## "Looks Done But Isn't" Checklist

- [ ] **JailbreakDetector:** Default keyword list tested with false-positive cases (not just adversarial ones) — verify legitimate prompts using attack vocabulary pass
- [ ] **ContentFilter:** Concurrent execution tested with shared filter function — verify no state collisions
- [ ] **ToolPolicy:** Allowlist mode tested independently of denylist mode — verify both modes work correctly
- [ ] **Policy behaviour:** `check/2` defined as `@callback` (required), not `@optional_callback` — verify compiler warns when omitted
- [ ] **Halt semantics:** `{:halt, violation}` return type (not `{:error, violation}`) — verify telemetry event names are distinct from error events
- [ ] **Backward compatibility:** All existing tests in `PhoenixAI.chat/2`, `stream/2`, `Agent`, `Pipeline`, `Team` pass without modification after guardrails ships
- [ ] **Request struct:** `metadata` field exists and is accessible in all policy `check/2` calls
- [ ] **Preset extensibility:** Documentation includes example showing `Guardrails.preset(:strict) ++ [MyPolicy.new()]`
- [ ] **Stateless guarantee:** No policy module in `PhoenixAI.Guardrails.*` has a `start_link/1` or uses `Process.put/get`
- [ ] **PolicyViolation struct:** Does not contain raw offending message content by default

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Stateful policy leaked into core | HIGH | Extract state to consumer-owned process; redesign `check/2` as pure; release as breaking change with migration guide |
| Halt semantics used wrong tuple | MEDIUM | Rename return tuple in `check/2` spec; update all policy implementations; update executor; add deprecation warning if needed |
| Request struct missing metadata | MEDIUM | Add `metadata: map()` field with default `%{}`; no breaking change if added before consumers ship |
| Mandatory guardrails broke existing callers | HIGH | Revert integration point; make opt-in; release patch; communicate via changelog |
| Keyword list too aggressive (high FPR) | LOW | Add `threshold` and `scope` options to JailbreakDetection policy; existing callers unaffected if options are optional |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| G1: Stateful policy leaking into core | Policy behaviour + Request struct design | `mix test` from multiple concurrent processes; no GenServer in guardrails modules |
| G2: Keyword detection false positives | JailbreakDetector implementation | False-positive test suite with legitimate prompts; `threshold` and `scope` options present |
| G3: Halt vs error semantics | Policy behaviour definition | `check/2` typespec uses `{:halt, ...}` not `{:error, ...}`; telemetry event names distinct |
| G4: Mandatory guardrails breaking existing API | Architecture / integration design | All pre-guardrails tests pass unchanged after merge |
| G5: ToolPolicy denylist as security guarantee | ToolPolicy implementation | Allowlist mode tests present; denylist limitations documented in module doc |
| G6: ContentFilter with mutable closure | ContentFilter implementation | Concurrent execution test with shared filter function |
| G7: Policy ordering undocumented | Pipeline executor implementation | Ordering documented; cross-ordering test present for same input |
| G8: Request struct missing context | Request struct definition | `metadata` field on struct; per-user ToolPolicy test using metadata |
| G9: Preset not extensible | Preset implementation | `preset/1` returns a plain list; extension pattern documented |
| G10: Optional callback silent no-op | Policy behaviour definition | `check/2` is `@callback`; compile-time warning test present |

---

## Sources

### Guardrails-specific

- [Bypassing Prompt Injection and Jailbreak Detection in LLM Guardrails — arxiv.org](https://arxiv.org/html/2504.11168v1) — MEDIUM confidence (character injection, Unicode obfuscation bypass techniques)
- [The Denylist Delusion: Cursor's Auto-Run Leaves Agentic AI Wide Open — Backslash Security](https://www.backslash.security/blog/cursor-ai-security-flaw-autorun-denylist) — MEDIUM confidence (denylist bypass patterns)
- [Prompt injection to RCE in AI agents — Trail of Bits](https://blog.trailofbits.com/2025/10/22/prompt-injection-to-rce-in-ai-agents/) — MEDIUM confidence (tool calling security model)
- [LLM Guardrails Best Practices — Datadog](https://www.datadoghq.com/blog/llm-guardrails-best-practices/) — MEDIUM confidence (false positive rates, production tuning)
- [Architecting Guardrails and Validation Layers — DEV Community](https://dev.to/shreekansha97/architecting-guardrails-and-validation-layers-in-generative-ai-systems-5c1c) — MEDIUM confidence (middleware layering patterns)
- [AI Agent Guardrails — UX Planet](https://uxplanet.org/guardrails-for-ai-agents-24349b93caeb) — MEDIUM confidence (false positive UX impact, competitor name filter example)
- [Guardrails AI — GitHub](https://github.com/guardrails-ai/guardrails) — MEDIUM confidence (library design reference, optional callback patterns)
- [OpenAI Agents SDK — Guardrails](https://openai.github.io/openai-agents-python/guardrails/) — HIGH confidence (input/output guardrail separation, halt semantics)
- [Optional callbacks — Elixir issue #5735](https://github.com/elixir-lang/elixir/issues/5735) — HIGH confidence (silent no-op risk with @optional_callbacks)
- [Absinthe.Middleware — hexdocs](https://hexdocs.pm/absinthe/Absinthe.Middleware.html) — HIGH confidence (Elixir middleware behaviour pattern reference)
- [MCP Interceptors proposal — modelcontextprotocol/modelcontextprotocol#1763](https://github.com/modelcontextprotocol/modelcontextprotocol/issues/1763) — MEDIUM confidence (M×N middleware composability problem)
- [Plug.Builder halt/1 — hexdocs](https://hexdocs.pm/plug/Plug.Builder.html) — HIGH confidence (halt-on-first pattern reference)

---
*Guardrails pitfalls section added: 2026-04-04*
*Downstream consumer: v0.3.0 roadmap and phase planning*
