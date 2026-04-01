# Phase 7: Streaming + Tools Integration - Context

**Gathered:** 2026-03-30
**Status:** Ready for planning

<domain>
## Phase Boundary

Streaming and tool calling work correctly together for both OpenAI and Anthropic. During a streaming response, tool call deltas are accumulated into complete `%ToolCall{}` structs, tools are executed, results are injected back, and the provider is re-called via streaming. Chunks are delivered to callers via callback (`:on_chunk`) or PID (`:to`) — including tool call delta chunks for full transparency.

**Not in scope:** New delivery mechanisms beyond callback/PID (already decided in Phase 6), changes to the synchronous ToolLoop (Phase 3), new tool behaviour callbacks.

</domain>

<decisions>
## Implementation Decisions

### Tool Call Delta Accumulation
- **D-01:** Tool call deltas are accumulated in the existing accumulator map inside `Stream.run/4`. New fields (e.g., `tool_calls_in_progress`) are added to the acc map — same pattern as content accumulation. No separate module or stateful parse_chunk.
- **D-02:** `parse_chunk/1` signals tool call deltas via the existing `StreamChunk.tool_call_delta` field (already in the struct since Phase 6). Returns `%StreamChunk{tool_call_delta: %{index: 0, name: "fn", arguments: "..."}}`. Zero interface change.
- **D-03:** When `finish_reason` arrives, the accumulated fragments are assembled into complete `%ToolCall{}` structs with full name and decoded JSON arguments.

### Stream + Tool Loop
- **D-04:** The streaming tool loop is implemented by extending `Stream.run/4` (or a wrapper like `stream_with_tools/4`). When a stream completes with accumulated tool_calls, tools are executed, results are injected into messages, and `Stream.run/4` is re-called. No new loop module — reuses all existing streaming infrastructure.
- **D-05:** All re-calls after tool execution are also streaming — never falls back to synchronous `chat/2`. If the user asked for stream, they get stream all the way through. Consistency with consumer expectations.
- **D-06:** Maximum iterations follow the same pattern as ToolLoop: default 10, configurable via `:max_iterations` in opts. Returns `{:error, :max_iterations_reached}` if exceeded.

### Tool Chunk Delivery
- **D-07:** The callback/PID receives ALL chunks, including those with `tool_call_delta` populated. Maximum transparency — the consumer decides what to do (e.g., show "Calling get_weather..." in the UI). No filtering.
- **D-08:** The existing delivery mechanism from Phase 6 is unchanged: `:on_chunk` callback receives `%StreamChunk{}`, `:to` PID receives `{:phoenix_ai, {:chunk, %StreamChunk{}}}`. The only difference is that some chunks now have `tool_call_delta` populated.

### SSE Fixture Strategy
- **D-09:** Fixture files in `test/fixtures/sse/` — same strategy as Phase 6. New files: `openai_tool_call.sse`, `anthropic_tool_call.sse` with realistic tool call streaming data. Reproducible, no network calls.
- **D-10:** Fixtures must capture the full tool call streaming sequence: initial text chunks, tool call delta chunks (name, fragmented arguments), and the finish sentinel. Both OpenAI and Anthropic formats required.

### Public API
- **D-11:** `AI.stream/2` is extended to accept `tools: [MyTool1, MyTool2]` option. When tools are present, streaming uses the tool-aware loop. Without tools, behavior is unchanged from Phase 6.
- **D-12:** Return value remains `{:ok, %Response{}}` with the final accumulated content and any tool_calls from the last iteration.

### Claude's Discretion
- Internal helper functions for assembling tool call fragments into complete ToolCalls
- Whether `stream_with_tools` is a separate function or integrated into `Stream.run/4` via opts detection
- How tool execution integrates with the streaming accumulator reset between iterations
- Exact structure of `tool_call_delta` map fields per provider (index, id, name, arguments fragment)
- Whether OpenRouter gets its own tool call fixture or reuses OpenAI's (given API compatibility)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Prior Phase Context
- `.planning/phases/03-tool-calling/03-CONTEXT.md` — D-01/D-03: Tool behaviour (plain modules, no OTP), D-08/D-10: per-adapter tool result injection, D-12/D-14: ToolLoop design (recursive, max iterations), D-16/D-17: tool error handling (send error back to provider, don't abort)
- `.planning/phases/06-streaming-transport/06-CONTEXT.md` — D-01/D-03: stream/2 API with on_chunk/to, D-05: PID message format, D-08/D-11: per-provider parse_chunk/1 and sentinel detection, D-12/D-13: Finch direct + one Task per session

### Existing Code (streaming + tools intersection)
- `lib/phoenix_ai/stream.ex` — Stream.run/4 with Finch accumulator, process_sse_events/2, apply_chunk/2 — the module to extend
- `lib/phoenix_ai/stream_chunk.ex` — %StreamChunk{delta, tool_call_delta, finish_reason, usage} — tool_call_delta field already present
- `lib/phoenix_ai/tool_loop.ex` — ToolLoop.run/4 with recursive do_loop, execute_and_build_results — pattern to follow for streaming variant
- `lib/phoenix_ai/providers/openai.ex` — parse_chunk/1 (lines 132-143) — needs extension for tool call chunks
- `lib/phoenix_ai/providers/anthropic.ex` — parse_chunk/1 (lines 110-125) — needs extension for content_block_start (tool_use) and content_block_delta (input_json_delta)
- `lib/phoenix_ai/providers/openrouter.ex` — parse_chunk/1 delegates to OpenAI (line 123)
- `lib/ai.ex` — stream/2 public API (line 39) — needs tools: option handling
- `lib/phoenix_ai/tool_call.ex` — %ToolCall{id, name, arguments} struct — target for assembled deltas
- `lib/phoenix_ai/tool_result.ex` — %ToolResult{tool_call_id, content, error} struct

### Existing Fixtures
- `test/fixtures/sse/openai_simple.sse` — OpenAI text-only streaming (reference for format)
- `test/fixtures/sse/anthropic_simple.sse` — Anthropic text-only streaming (reference for format)
- `test/fixtures/sse/openai_fragmented.sse` — Fragmentation test (reference for edge cases)

### Provider SSE + Tool Call Documentation
- OpenAI Streaming with Tools: `https://platform.openai.com/docs/api-reference/streaming` (tool_calls in delta)
- Anthropic Streaming with Tools: `https://docs.anthropic.com/en/api/messages-streaming` (content_block_start type:tool_use, input_json_delta events)

### Project Research
- `.planning/research/PITFALLS.md` — SSE fragmentation pitfalls, streaming + tool interaction must be tested as a unit

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `%StreamChunk{tool_call_delta: map()}` — field already exists, ready to populate
- `Stream.run/4` accumulator pattern — extend with `tool_calls_in_progress` field
- `Stream.apply_chunk/2` — extend to handle tool_call_delta accumulation
- `ToolLoop.execute_and_build_results/3` — reuse for tool execution after stream accumulation
- `ToolLoop.build_assistant_message/1` — reuse for building assistant message with tool calls
- All provider `format_tools/1` implementations — already working from Phase 3
- All provider `format_messages/1` with tool result injection — already working from Phase 3
- `Stream.build_stream_body` already receives opts — tools_json can pass through

### Established Patterns
- Accumulator map in Stream.run/4 for stateful processing during Finch.stream
- parse_chunk/1 returns %StreamChunk{} with relevant fields populated, nil for skip
- Provider adapters own their wire format translation (tool call parsing differs between OpenAI and Anthropic)
- {:ok, result} | {:error, reason} return tuples everywhere
- SSE fixture files for reproducible testing

### Integration Points
- `Stream.run/4` — main extension point for tool loop logic
- Each provider's `parse_chunk/1` — extend for tool call delta events
- `AI.stream/2` — add `tools:` option detection and routing
- `Stream.build_stream_body` — inject formatted tools into stream request body
- Test infrastructure — new fixture files + integration tests

</code_context>

<specifics>
## Specific Ideas

- The `tool_call_delta` field in StreamChunk was deliberately added in Phase 6 as forward-compatibility for this phase — no struct changes needed
- OpenAI sends tool calls as `delta.tool_calls[{index, function.name, function.arguments}]` — index is critical for parallel tool calls
- Anthropic sends tool calls as separate content blocks: `content_block_start` (type: tool_use, id, name) followed by `content_block_delta` (type: input_json_delta, partial_json) — the event type drives the state machine
- Delivering tool_call_delta chunks to the consumer enables real-time UI updates like "Calling get_weather..." or showing argument assembly progress
- The re-call being streaming means a LiveView consumer gets real-time chunks even for the final response after tool execution — no "dead air" while waiting for the post-tool response

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 07-streaming-tools-integration*
*Context gathered: 2026-03-30*
