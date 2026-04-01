# Phase 3: Tool Calling - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-29
**Phase:** 03-tool-calling
**Areas discussed:** Tool behaviour design, Tool result injection, Auto-loop design, Schema format, Error handling, format_tools/1, API pública

---

## Tool Behaviour Design

| Option | Description | Selected |
|--------|-------------|----------|
| Behaviour with callbacks | Modules with use PhoenixAI.Tool and callbacks: name/0, description/0, parameters_schema/0, execute/2. | ✓ |
| Map inline (anonymous) | Tools defined as inline maps with anonymous execute functions. | |
| Both | Behaviour for reusable tools + maps for one-offs. | |

**User's choice:** Behaviour with callbacks only
**Notes:** User asked about Elixir philosophy. Maps with anonymous functions is a JavaScript anti-pattern in Elixir — behaviours are the idiomatic way. "Both" adds complexity for two ways to do the same thing.

---

## execute/2 Context Parameter

| Option | Description | Selected |
|--------|-------------|----------|
| Opts keyword list | Same opts passed to chat/2 — gives access to api_key, model, provider, metadata. | ✓ |
| Dedicated struct | %PhoenixAI.ToolContext{} with specific fields. | |
| No context (args only) | execute/1 with only arguments. | |

**User's choice:** Opts keyword list (Recommended)
**Notes:** Consistent with existing config cascade pattern. No new structs needed.

---

## Tool Result Injection Per-Provider

| Option | Description | Selected |
|--------|-------------|----------|
| Inside format_messages | Each adapter translates tool results in its own format_messages/1. | ✓ |
| Separate inject_tool_results/2 | Dedicated function per adapter for tool result transformation. | |
| Claude decide | Best technical approach. | |

**User's choice:** Inside format_messages (Recommended)
**Notes:** Zero shared code. OpenAI already handles :tool role. Anthropic needs new clause for content block format.

---

## Auto-Loop Location

| Option | Description | Selected |
|--------|-------------|----------|
| PhoenixAI.ToolLoop module | Pure function module, recursive, no state. Reusable by Agent GenServer. | ✓ |
| Inside AI module | AI.chat_with_tools/3 encapsulating the loop. | |
| Inside each adapter | Each provider implements its own loop. | |

**User's choice:** PhoenixAI.ToolLoop module (Recommended)
**Notes:** Pure module, no GenServer. Phase 4 Agent will reuse it.

---

## Max Iterations

| Option | Description | Selected |
|--------|-------------|----------|
| Default 10 | max_iterations: 10, override via opts. {:error, :max_iterations_reached} if exceeded. | ✓ |
| Default 5 | More conservative. | |
| No limit | Trust provider to stop. | |

**User's choice:** Default 10 (Recommended)

---

## Error Handling in Tools

| Option | Description | Selected |
|--------|-------------|----------|
| Send error to provider | {:error, reason} and exceptions become error tool results sent to model. Loop only aborts on network/provider errors. | ✓ |
| Abort the loop | Any tool error aborts loop, returns {:error, {:tool_failed, name, reason}}. | |
| Claude decide | Best approach for robustness. | |

**User's choice:** Send error to provider (Recommended)
**Notes:** Model gets the error and can respond gracefully (e.g., "I couldn't find that city").

---

## format_tools/1 Implementation

| Option | Description | Selected |
|--------|-------------|----------|
| Shared helper + adapter wrapper | PhoenixAI.Tool.to_json_schema/1 converts atom→string keys. Each adapter wraps in provider envelope. | ✓ |
| All in adapter | Each adapter does full conversion. More duplication. | |
| Claude decide | Best balance. | |

**User's choice:** Helper + adapter wrapper (Recommended)
**Notes:** to_json_schema/1 is generic data conversion. Provider-specific envelope is per-adapter.

---

## Schema Format

| Option | Description | Selected |
|--------|-------------|----------|
| Plain maps with atom keys | JSON Schema as Elixir maps with atom keys. format_tools/1 converts to string keys per provider. | ✓ |
| String-keyed maps | JSON Schema with string keys, direct API format. | |
| DSL builder | Macros for schema definition. | |

**User's choice:** Atom keys (Recommended)
**Notes:** User asked about Elixir/Phoenix philosophy. Atom keys internally, string keys at boundary — standard Elixir pattern (same as Ecto, NimbleOptions).

---

## Public API

| Option | Description | Selected |
|--------|-------------|----------|
| AI.chat with tools: option | Extend AI.chat/2 to accept tools: [MyTool]. Auto-invokes ToolLoop when present. | ✓ |
| Separate AI.run/3 | AI.chat for simple, AI.run for tools. | |
| Only ToolLoop public | ToolLoop.run/4 only, integrate in Phase 4. | |

**User's choice:** AI.chat with tools: option (Recommended)
**Notes:** Unified API — one function to learn.

---

## Claude's Discretion

- Internal ToolLoop helper functions
- Exact atom→string conversion logic
- How to detect "no more tool calls"
- Whether format_tools/1 becomes required callback
- Test fixture design

## Deferred Ideas

None — discussion stayed within phase scope
