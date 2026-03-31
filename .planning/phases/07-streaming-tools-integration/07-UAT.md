---
status: complete
phase: 07-streaming-tools-integration
source: PLAN.md, git log e90f825..2c362f4
started: 2026-03-30T23:45:00Z
updated: 2026-03-30T23:50:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Mid-Stream Tool Call Events Parsed Correctly (OpenAI)
expected: OpenAI parse_chunk/1 extracts tool_call_delta from delta.tool_calls — id, name, index, and argument fragments. Handles first chunk (with id/name) and subsequent chunks (arguments only). Text-only chunks still work.
result: pass
evidence: test/phoenix_ai/providers/openai_stream_tools_test.exs — 4 tests passing. lib/phoenix_ai/providers/openai.ex:134-155 — extract_tool_call_delta/1 handles nil, empty list, and tool call entries.

### 2. Mid-Stream Tool Call Events Parsed Correctly (Anthropic)
expected: Anthropic parse_chunk/1 handles content_block_start with type "tool_use" (returns tool_call_delta with index, id, name) and content_block_delta with type "input_json_delta" (returns tool_call_delta with arguments fragment). Text deltas and other events still work.
result: pass
evidence: test/phoenix_ai/providers/anthropic_stream_tools_test.exs — 5 tests passing. lib/phoenix_ai/providers/anthropic.ex:109-150 — event-type dispatch for tool_use and input_json_delta.

### 3. Tool Call Delta Accumulation in Stream
expected: Stream accumulator (tool_calls_acc map) merges tool call fragments by index. When stream completes, build_response/1 assembles complete %ToolCall{} structs with decoded JSON arguments. Handles parallel tool calls (index 0, 1), empty arguments, and malformed JSON.
result: pass
evidence: test/phoenix_ai/stream_test.exs — 4 accumulation tests passing. lib/phoenix_ai/stream.ex:137-151 — apply_chunk for tool_call_delta, :170-186 — build_response with decode_arguments.

### 4. Stream.run_with_tools/5 Recursive Loop
expected: run_with_tools/5 wraps run/4 with tool call detection. When stream completes with tool_calls, executes tools (via ToolLoop helpers), injects results, and re-streams. Returns {:error, :max_iterations_reached} when limit exceeded.
result: pass
evidence: lib/phoenix_ai/stream.ex:60-97 — run_with_tools/5 + do_stream_loop/7. test/phoenix_ai/stream_tools_test.exs — max_iterations test passing.

### 5. AI.stream/2 Accepts tools: Option
expected: AI.stream/2 with tools: [MyTool] routes to Stream.run_with_tools/5. Without tools, routes to Stream.run/4. The tools: option is stripped from stream opts.
result: pass
evidence: lib/ai.ex:63-76 — dispatch_stream detects tools and routes. test/phoenix_ai/ai_stream_tools_test.exs — 3 routing tests passing.

### 6. AI.stream/2 with on_chunk Delivers Tool Call Delta Chunks
expected: The on_chunk callback receives ALL StreamChunk structs including those with tool_call_delta populated. Text chunks and tool call delta chunks both delivered in arrival order.
result: pass
evidence: test/phoenix_ai/stream_tools_test.exs:130-153 — callback delivery test asserts text chunks ("Let me", " check.") AND tool_call_delta chunk (name: "get_weather") all received.

### 7. AI.stream/2 with to: pid Sends Messages
expected: PID delivery mechanism unchanged from Phase 6. Sends {:phoenix_ai, {:chunk, %StreamChunk{}}} to target process.
result: pass
evidence: lib/ai.ex:56 — build_callback PID branch unchanged. Phase 6 PID delivery tests still pass (part of 234 test suite).

### 8. OpenAI Fixture End-to-End
expected: openai_tool_call.sse fixture parses correctly through full pipeline: SSE → parse_chunk → accumulator → Response with content "Let me check.", ToolCall{name: "get_weather", arguments: %{"city" => "London"}}, and usage data.
result: pass
evidence: test/phoenix_ai/stream_tools_test.exs:76-102 — OpenAI fixture test. test/fixtures/sse/openai_tool_call.sse exists with realistic SSE data.

### 9. Anthropic Fixture End-to-End
expected: anthropic_tool_call.sse fixture parses correctly: text content block followed by tool_use content block. Response has content "Let me check." and ToolCall{id: "toolu_abc123", name: "get_weather"} with city argument.
result: pass
evidence: test/phoenix_ai/stream_tools_test.exs:104-127 — Anthropic fixture test. test/fixtures/sse/anthropic_tool_call.sse exists with realistic SSE data.

### 10. ToolLoop Helpers Public for Reuse
expected: build_assistant_message/1 and execute_and_build_results/3 are public functions with @doc. Stream.run_with_tools/5 reuses them without duplication.
result: pass
evidence: lib/phoenix_ai/tool_loop.ex — both functions are `def` with @doc. test/phoenix_ai/tool_loop_helpers_test.exs — 3 tests passing.

### 11. build_stream_body Injects Tools
expected: Each provider's build_stream_body already handles tools_json via existing maybe_put/inject_schema_and_tools patterns. No changes needed — tools pass through opts correctly.
result: pass
evidence: lib/phoenix_ai/providers/openai.ex:107-111 — build_stream_body delegates to build_body which calls maybe_put("tools", ...). lib/phoenix_ai/providers/anthropic.ex:83-86 — same via inject_schema_and_tools. Verified by existing Phase 3 tool tests still passing.

### 12. Actual finish_reason Preserved
expected: build_response uses actual finish_reason from stream (e.g., "stop", "tool_calls", "tool_use") instead of hardcoding "stop". Code review finding fixed.
result: pass
evidence: lib/phoenix_ai/stream.ex:46 — finish_reason: nil in acc. :167 — new_finish_reason captured from chunk. :183 — Map.get(acc, :finish_reason) || "stop" fallback.

### 13. Full Test Suite Green
expected: `mix test` passes with 0 failures. All 234 tests pass including 25 new streaming+tools tests.
result: pass
evidence: `mix test` → "234 tests, 0 failures" (0.5 seconds).

### 14. Code Quality (Credo)
expected: `mix credo --strict` passes with no issues. All new code follows project conventions.
result: pass
evidence: `mix credo --strict` → "310 mods/funs, found no issues."

## Summary

total: 14
passed: 14
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps

[none]
