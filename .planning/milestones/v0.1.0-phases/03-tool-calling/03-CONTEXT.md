# Phase 3: Tool Calling - Context

**Gathered:** 2026-03-29
**Status:** Ready for planning

<domain>
## Phase Boundary

Tools are callable modules implementing a behaviour, tool result injection is handled per-provider inside `format_messages/1`, and the automatic tool loop (call → detect → execute → re-call → until stop) runs via a dedicated `PhoenixAI.ToolLoop` module. The round-trip works correctly for both OpenAI and Anthropic wire formats. `AI.chat/2` is extended to accept `tools:` option.

</domain>

<decisions>
## Implementation Decisions

### Tool Behaviour
- **D-01:** Tools are defined ONLY as modules implementing `PhoenixAI.Tool` behaviour. No map/anonymous function support — this follows the Elixir idiom of behaviours for contracts (same pattern as Ecto.Repo, Plug, etc.).
- **D-02:** `PhoenixAI.Tool` behaviour defines 4 callbacks: `name/0` (string), `description/0` (string), `parameters_schema/0` (map with atom keys), `execute/2` (args map + opts keyword list).
- **D-03:** Tools are plain modules — no OTP, no GenServer, no processes. They implement callbacks and that's it.
- **D-04:** `execute/2` receives `(args, opts)` where args is the decoded arguments map (string keys from provider) and opts is the same keyword list passed to `AI.chat/2`. Returns `{:ok, result_string}` or `{:error, reason}`.

### Parameters Schema
- **D-05:** Schema is defined as plain Elixir maps with atom keys following JSON Schema structure: `%{type: :object, properties: %{city: %{type: :string, description: "City name"}}, required: [:city]}`.
- **D-06:** A shared helper `PhoenixAI.Tool.to_json_schema/1` converts atom-keyed schema to string-keyed JSON Schema maps. This is generic conversion, not provider-specific.
- **D-07:** Each adapter's `format_tools/1` calls `to_json_schema/1` and wraps the result in the provider-specific envelope (OpenAI: `type: "function"` wrapper, Anthropic: `input_schema` key).

### Tool Result Injection (PROV-04)
- **D-08:** Tool result injection is handled INSIDE each adapter's `format_messages/1` — no shared injection code. Each adapter owns its wire format translation.
- **D-09:** OpenAI: tool results become `role: "tool"` messages with `tool_call_id` and `content` (already partially implemented in Phase 1-2 format_message clauses).
- **D-10:** Anthropic: tool results become `role: "user"` messages with content block `type: "tool_result"`, `tool_use_id`, and `content`. This requires extending the Anthropic adapter's `format_message/1` to handle `:tool` role messages with the Anthropic-specific content block format.
- **D-11:** OpenRouter: same as OpenAI format (API-compatible). Already handled by existing format_message clauses.

### Auto-Loop (ToolLoop)
- **D-12:** The tool loop lives in a dedicated `PhoenixAI.ToolLoop` module — pure function, no GenServer, no state. Recursive call until `finish_reason` indicates stop (no more tool calls).
- **D-13:** `ToolLoop.run/4` signature: `run(provider_mod, messages, tools, opts)`. Returns `{:ok, %Response{}}` (final response) or `{:error, reason}`.
- **D-14:** Maximum iterations default is 10, configurable via `max_iterations:` in opts. Returns `{:error, :max_iterations_reached}` if exceeded.
- **D-15:** The Agent GenServer (Phase 4) will reuse this module — it's designed as a reusable building block.

### Error Handling
- **D-16:** When `tool.execute/2` returns `{:error, reason}`, the error is sent to the provider as a tool result (via `ToolResult.error` field). The model decides how to respond. The loop does NOT abort on tool errors.
- **D-17:** When `tool.execute/2` raises an exception, it is rescued and the exception message is sent as an error tool result. Same treatment as `{:error, reason}`.
- **D-18:** The loop ONLY aborts on provider/network errors (i.e., when `provider_mod.chat/2` returns `{:error, _}`).

### Public API
- **D-19:** `AI.chat/2` is extended to accept `tools: [MyTool1, MyTool2]` option. When tools are present, it automatically invokes `ToolLoop.run/4`. Without tools, behavior is unchanged from Phase 1-2.
- **D-20:** `max_iterations:` option is passed through to ToolLoop when tools are present.

### Claude's Discretion
- Internal ToolLoop helper functions (assistant_msg, tool_result_msgs construction)
- Exact atom→string conversion logic in `to_json_schema/1`
- How `chat/2` detects "no more tool calls" (empty list vs finish_reason check)
- Whether `format_tools/1` becomes a required callback or stays optional (depends on how AI.chat integrates it)
- Test fixture design for tool calling round-trips

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project Research
- `.planning/research/ARCHITECTURE.md` — Provider behaviour contract, format_tools/1 definition
- `.planning/research/PITFALLS.md` — Tool calling pitfalls and wire format differences
- `.planning/research/SUMMARY.md` — Top decisions including tool calling approach

### Prior Phase Context
- `.planning/phases/01-core-foundation/01-CONTEXT.md` — Provider behaviour, naming conventions, struct definitions
- `.planning/phases/02-remaining-providers/02-CONTEXT.md` — Anthropic content block note (D-06: "content blocks with types needed in Phase 3")

### Existing Code
- `lib/phoenix_ai/provider.ex` — Provider behaviour with `format_tools/1` as `@optional_callback`
- `lib/phoenix_ai/tool_call.ex` — `%ToolCall{id, name, arguments}` struct
- `lib/phoenix_ai/tool_result.ex` — `%ToolResult{tool_call_id, content, error}` struct
- `lib/phoenix_ai/providers/openai.ex` — OpenAI adapter with existing `format_message` for `:tool` role and `parse_tool_calls`
- `lib/phoenix_ai/providers/anthropic.ex` — Anthropic adapter with `extract_tool_calls` from content blocks (parse side done, injection side needs extending)
- `lib/phoenix_ai/providers/openrouter.ex` — OpenRouter adapter with OpenAI-compatible format_message for `:tool` role
- `lib/ai.ex` — Public API, will need `tools:` option handling

### Provider API Docs (tool calling specifics)
- OpenAI Function Calling: `https://platform.openai.com/docs/guides/function-calling`
- Anthropic Tool Use: `https://docs.anthropic.com/en/docs/build-with-claude/tool-use`

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `PhoenixAI.ToolCall` struct — already used by all 3 adapters to parse tool calls from responses
- `PhoenixAI.ToolResult` struct — exists with `tool_call_id`, `content`, `error` fields, ready for use
- OpenAI `format_message/1` for `:tool` role — already handles tool result messages correctly
- OpenRouter `format_message/1` for `:tool` role — same as OpenAI, already works
- All 3 adapters' `parse_tool_calls` / `extract_tool_calls` — parse side is complete from Phase 1-2
- `format_tools/1` callback — defined in Provider behaviour as `@optional_callback`, not yet implemented by any adapter

### Established Patterns
- Provider adapters are self-contained modules implementing `@behaviour PhoenixAI.Provider`
- Message formatting via `format_messages/1` with pattern-matched clauses per message type
- Error structs via `%PhoenixAI.Error{status:, message:, provider:}`
- Fixture-based testing with recorded JSON responses
- Contract tests verifying consistent output across adapters

### Integration Points
- `AI.chat/2` needs to detect `tools:` in opts and route to ToolLoop
- Each adapter's `format_messages/1` needs extension for Anthropic tool result content blocks
- Each adapter needs `format_tools/1` implementation (currently @optional_callback, no implementations)

</code_context>

<specifics>
## Specific Ideas

- Tool behaviour follows Elixir idiom — behaviours for contracts, not anonymous maps. Same pattern as Plug, Ecto.Repo.
- The `execute/2` context is the same opts keyword list from `chat/2` — no new structs, consistent with existing config cascade pattern
- Parameters schema uses atom keys internally (Elixir way) with automatic conversion to string keys at the provider boundary
- Helper `to_json_schema/1` is the only shared code between adapters — everything else is per-adapter. This is acceptable DRY since it's a generic data conversion, not business logic.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 03-tool-calling*
*Context gathered: 2026-03-29*
