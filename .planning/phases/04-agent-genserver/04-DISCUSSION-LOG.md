# Phase 4: Agent GenServer - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-29
**Phase:** 04-agent-genserver
**Areas discussed:** GenServer state & API, Supervision & isolation, Conversation accumulation, Integration com ToolLoop, System prompt, API auxiliar, Naming

---

## prompt/2 Sync vs Async

| Option | Description | Selected |
|--------|-------------|----------|
| Síncrono via GenServer.call | Blocks caller until complete. Simple, predictable. 60s timeout. | ✓ |
| Assíncrono via GenServer.cast | Returns immediately, response via message. | |
| Ambos | sync + async variants. | |

**User's choice:** Síncrono (Recommended)
**Notes:** User asked about Elixir/Phoenix philosophy and Laravel/AI. Both recommend sync for request-response. GenServer.call blocks the caller but not the BEAM. Laravel/AI is also synchronous.

---

## Timeout Default

| Option | Description | Selected |
|--------|-------------|----------|
| 60 seconds | Generous for tool loops. Override via prompt/3. | ✓ |
| :infinity | No timeout. Risky. | |
| 30 seconds | May be short for complex loops. | |

**User's choice:** 60 seconds (Recommended)

---

## Supervision

| Option | Description | Selected |
|--------|-------------|----------|
| Own child_spec | Compatible with DynamicSupervisor. Consumer decides where. | ✓ |
| No child_spec | Consumers use start_link only. | |

**User's choice:** Own child_spec (Recommended)

---

## Conversation History Management

| Option | Description | Selected |
|--------|-------------|----------|
| Lista simples no state | GenServer accumulates messages. | |
| Consumer gere | Consumer passes messages each call. | |
| Hybrid (manage_history opt) | Both modes via config. Default: managed. | ✓ |

**User's choice:** Hybrid
**Notes:** User questioned whether GenServer should hold history. Discussed that consumer-managed is important for persistence use cases. Agreed on hybrid: `manage_history: true` (default, like Laravel/AI) or `manage_history: false` (consumer passes messages). Both are valid OTP patterns for different use cases.

---

## Integration with ToolLoop

| Option | Description | Selected |
|--------|-------------|----------|
| Task.async in handle_call | GenServer spawns Task, replies via GenServer.reply when done. GenServer stays responsive. | ✓ |
| Direct in handle_call | Blocks GenServer during provider call. | |
| Claude decide | Best approach. | |

**User's choice:** Task.async
**Notes:** User asked about Elixir/OTP best practice. "Don't block the GenServer" — long-running ops should run in spawned Task. Pattern used by Ecto, Finch, Broadway. Caller still blocks (uses GenServer.call), but GenServer can handle other messages.

---

## System Prompt

| Option | Description | Selected |
|--------|-------------|----------|
| Opt in start_link, immutable | Set once, prepended always. Cannot change after init. | ✓ |
| Mutable via set_system/2 | Can change after init. | |

**User's choice:** Immutable (Recommended)

---

## Auxiliary API

| Option | Description | Selected |
|--------|-------------|----------|
| get_messages/1 | Returns accumulated messages. | ✓ |
| reset/1 | Clears history, keeps config. | ✓ |
| None | YAGNI. | |

**User's choice:** Both get_messages/1 and reset/1

---

## Naming

| Option | Description | Selected |
|--------|-------------|----------|
| Only PID | YAGNI, v2 feature. | |
| Support :name opt | Accept GenServer-compatible names. | ✓ |

**User's choice:** Support :name opt

---

## Claude's Discretion

- GenServer state struct design
- Task.async/handle_info plumbing details
- Error handling for Task failures
- Test fixtures and Mox setup

## Deferred Ideas

- V2-02: Full Registry/via_tuple patterns for named agents
- V2-03: Inline anonymous agent helper
