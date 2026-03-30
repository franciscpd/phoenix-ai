# Phase 6: Streaming Transport - Context

**Gathered:** 2026-03-30
**Status:** Ready for planning

<domain>
## Phase Boundary

Server-Sent Events streaming via Finch (not Req) for all three provider adapters. Includes a stateful SSE parser with `\n\n` boundary detection, provider-specific `parse_chunk/1` implementations that convert raw SSE data to `%StreamChunk{}` structs, and a `PhoenixAI.stream/2` public API that delivers chunks via message passing or callback. Each streaming session spawns one Task — no shared GenServer bottleneck.

**Not in scope:** Streaming + tool calling combined (Phase 7), callback/PID delivery API design beyond basic transport (Phase 7).

</domain>

<decisions>
## Implementation Decisions

### SSE Parser
- **D-01:** Use the `server_sent_events` hex package (~> 0.2) for SSE parsing. No custom parser — the lib handles stateful buffer accumulation, `\n\n` boundary detection, and TCP fragment reassembly.
- **D-02:** The parser is a dependency added to `mix.exs`, not vendored or reimplemented.

### API Surface
- **D-03:** `PhoenixAI.stream/2` accepts `(messages, opts)`. Chunk delivery is configured via opts: `:on_chunk` for callback, `:to` for PID-based message passing. No positional callback argument.
- **D-04:** Default delivery: when neither `:on_chunk` nor `:to` is provided, chunks are sent to `self()` — idiomatic Elixir message passing, integrates naturally with LiveView `handle_info/2`.
- **D-05:** Message format for PID delivery: `{:phoenix_ai, {:chunk, %StreamChunk{}}}` — namespaced to avoid collision with other messages in the caller's mailbox.
- **D-06:** `stream/2` returns `{:ok, %Response{content: "full accumulated text", usage: %{...}}}` when the stream completes. Caller gets both real-time chunks AND the final accumulated Response for logging/billing.
- **D-07:** On error, returns `{:error, reason}` — same tuple pattern as `chat/2`.

### Wire Format per Provider
- **D-08:** Each adapter implements `parse_chunk/1` and is responsible for detecting its own stream-end sentinel. No shared sentinel detection logic.
- **D-09:** OpenAI/OpenRouter: `data: [DONE]` is the sentinel. Delta extracted from `choices[0].delta.content`. OpenRouter is API-compatible with OpenAI.
- **D-10:** Anthropic: `event: message_stop` is the sentinel. Delta extracted from `delta.text` in `content_block_delta` events. Event types (`content_block_start`, `content_block_delta`, `message_stop`) drive the state machine.
- **D-11:** `parse_chunk/1` returns `%StreamChunk{finish_reason: "stop"}` when it detects the sentinel — the streaming module stops when it sees a non-nil `finish_reason`.

### Streaming Architecture
- **D-12:** Streaming uses Finch directly (not Req) for long-running SSE connections — per STREAM-01 and the architectural decision from Phase 1.
- **D-13:** Each streaming session spawns exactly one Task — per STREAM-04. No shared singleton GenServer accumulating stream state.
- **D-14:** The Finch pool is already wired in `PhoenixAI.child_spec/1` (default name: `PhoenixAI.Finch`). Streaming uses this pool.

### Testing Strategy
- **D-15:** SSE parser unit tests use inline strings for readability. Fragmentation edge cases use binary fixtures (`.sse` files) for realism. Combination of both approaches.
- **D-16:** Full stream flow tests (Finch -> parser -> chunks -> Response) use Mox — consistent with the existing test strategy across all phases. No Bypass or HTTP fake server for v1.
- **D-17:** Mox mocks the provider's `stream/3` at the same level as `chat/2` is already mocked.

### Claude's Discretion
- Internal module structure for the streaming transport (e.g., `PhoenixAI.Stream`, `PhoenixAI.SSE`, or inline in providers)
- How `server_sent_events` integrates with Finch's chunked response callback
- Accumulator design for building the final `%Response{}` from chunks
- Whether OpenRouter's `parse_chunk/1` delegates to OpenAI's or duplicates (likely delegates given API compatibility)
- Exact fixture file organization for SSE binary test data
- `StreamChunk.tool_call_delta` handling deferred to Phase 7 — Phase 6 only needs `delta` and `finish_reason`

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Prior Phase Context
- `.planning/phases/01-core-foundation/01-CONTEXT.md` — D-05: call-site config cascade, D-09: Provider behaviour with @optional_callbacks, D-12: Mox testing strategy, D-14: Finch for streaming / Req for sync
- `.planning/phases/02-remaining-providers/02-CONTEXT.md` — Provider adapter patterns, wire format ownership
- `.planning/phases/05-structured-output/05-CONTEXT.md` — D-08: schema and tools coexist pattern (relevant for Phase 7 but informs adapter design)

### Existing Code (streaming-relevant)
- `lib/phoenix_ai/stream_chunk.ex` — `%StreamChunk{}` struct already exists with `delta`, `tool_call_delta`, `finish_reason`
- `lib/phoenix_ai/provider.ex` — `stream/3` and `parse_chunk/1` callbacks already defined as `@optional_callbacks`
- `lib/phoenix_ai.ex` — `child_spec/1` with Finch pool supervision already wired
- `lib/phoenix_ai/providers/openai.ex` — `build_body/3`, `parse_response/1` patterns to follow for streaming
- `lib/phoenix_ai/providers/anthropic.ex` — Different wire format, event-type-based parsing needed
- `lib/phoenix_ai/providers/openrouter.ex` — OpenAI-compatible, likely delegates
- `lib/ai.ex` — Public API module where `stream/2` will be added alongside `chat/2`

### Provider SSE Documentation
- OpenAI Streaming: `https://platform.openai.com/docs/api-reference/streaming`
- Anthropic Streaming: `https://docs.anthropic.com/en/api/messages-streaming`
- OpenRouter: OpenAI-compatible streaming format

### Project Research
- `.planning/research/PITFALLS.md` — SSE fragmentation pitfalls, don't parse line-by-line, don't use shared GenServer
- `.planning/research/ARCHITECTURE.md` — Two-path HTTP design (Finch for streaming, Req for sync)

### Hex Packages
- `server_sent_events` ~> 0.2 — SSE frame parser to be added as dependency

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `%StreamChunk{}` struct — already defined, ready to use
- `Provider.stream/3` callback — already in the behaviour, adapters just need to implement it
- `Provider.parse_chunk/1` callback — already in the behaviour
- `PhoenixAI.child_spec/1` — Finch pool already supervised
- `Mox` test infrastructure — `PhoenixAI.MockProvider` already configured for `chat/2`, extend for `stream/3`

### Established Patterns
- Provider behaviour with `@optional_callbacks` — `stream/3` and `parse_chunk/1` are already optional
- Each adapter owns its wire format translation (headers, body, response parsing)
- `{:ok, result} | {:error, reason}` tuple returns everywhere
- Call-site opts > config > env cascade for configuration
- `build_body/3` pattern in adapters for constructing request payloads

### Integration Points
- `lib/ai.ex` — Add `stream/2` public function alongside `chat/2`
- Each provider adapter — Implement `stream/3` and `parse_chunk/1`
- `mix.exs` — Add `server_sent_events` dependency
- Test support — Extend MockProvider expectations for `stream/3`

</code_context>

<specifics>
## Specific Ideas

- Message format `{:phoenix_ai, {:chunk, %StreamChunk{}}}` is namespaced to avoid collision — follows the Phoenix convention of tagged tuples
- Default `to: self()` makes IEx/script usage ergonomic: `stream(msgs, provider: :openai)` just works, chunks arrive in the caller's mailbox
- `server_sent_events` is deliberately small and focused — avoids pulling in a heavy HTTP framework just for SSE parsing
- The final `%Response{}` return allows consumers to log token usage from streaming calls without extra bookkeeping
- `tool_call_delta` in StreamChunk is deferred to Phase 7 — Phase 6 focuses purely on text streaming transport

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 06-streaming-transport*
*Context gathered: 2026-03-30*
