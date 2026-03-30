# Phase 4: Agent GenServer - Context

**Gathered:** 2026-03-29
**Status:** Ready for planning

<domain>
## Phase Boundary

A stateful GenServer that owns one conversation's state (messages, provider, tools, config) and runs the completion-tool-call loop via ToolLoop. Supervisable via DynamicSupervisor without auto-starting. Supports both managed and consumer-managed history modes.

</domain>

<decisions>
## Implementation Decisions

### GenServer API
- **D-01:** `PhoenixAI.Agent.start_link/1` accepts opts: `provider:`, `model:`, `system:`, `tools:`, `manage_history:`, `name:`, and any provider opts (api_key, etc.).
- **D-02:** `PhoenixAI.Agent.prompt/2` is synchronous via `GenServer.call` with configurable timeout. The caller blocks until the full tool loop completes. Default timeout: 60 seconds.
- **D-03:** `PhoenixAI.Agent.prompt/3` accepts a third argument for per-call opts (e.g., `messages:` for consumer-managed history, timeout override).

### History Management (Hybrid)
- **D-04:** `manage_history: true` (default) — Agent accumulates messages in GenServer state. Each `prompt/2` adds user message + all intermediate messages (tool calls, tool results) + final response to state.
- **D-05:** `manage_history: false` — Agent does NOT accumulate. Consumer passes `messages:` in each `prompt/3` call. Agent acts as a stateless "runner" wrapping the ToolLoop.
- **D-06:** This hybrid pattern mirrors Laravel/AI where the Agent manages history by default but allows external injection via `withMessages()`.

### System Prompt
- **D-07:** System prompt passed via `system:` opt in `start_link/1`. Immutable after init. Prepended as first message before history in every provider call.
- **D-08:** If no system prompt provided, omitted entirely (not an empty string).

### GenServer Internals
- **D-09:** Long-running provider calls (HTTP + tool loop) run in a `Task.async` spawned from `handle_call`. The GenServer returns `{:noreply, state}` and replies via `GenServer.reply/2` in `handle_info` when the Task completes. This follows OTP best practice — the GenServer stays responsive while the provider call runs.
- **D-10:** The Task is monitored. If it crashes, the GenServer handles the DOWN message and replies with `{:error, reason}` to the caller.

### Supervision & Isolation
- **D-11:** `PhoenixAI.Agent` has its own `child_spec/1` returning a standard GenServer spec. Compatible with `DynamicSupervisor.start_child/2`.
- **D-12:** The library does NOT auto-start any supervisor for agents. Consumers own the supervision tree.
- **D-13:** Each agent is an independent process. Crashing one agent (via `Process.exit(pid, :kill)`) does not affect other agents. This is guaranteed by OTP process isolation — no shared state between agents.

### Naming
- **D-14:** Agent supports optional `:name` opt in `start_link/1`. Accepts any GenServer-compatible name: atom, `{:via, module, term}`, `{:global, term}`. If not provided, agent is referenced by PID only.

### Auxiliary API
- **D-15:** `PhoenixAI.Agent.get_messages/1` — returns the accumulated message list from state. Returns `[]` if `manage_history: false`.
- **D-16:** `PhoenixAI.Agent.reset/1` — clears message history, keeps config (provider, tools, system). Restarts the conversation. No-op if `manage_history: false`.

### Integration with ToolLoop
- **D-17:** Agent delegates to `PhoenixAI.ToolLoop.run/4` when tools are configured. When no tools, calls `provider_mod.chat/2` directly. Same logic as `AI.chat/2` but with stateful message accumulation.
- **D-18:** The accumulated messages (including system prompt) are passed to ToolLoop. ToolLoop returns `{:ok, %Response{}}` which the Agent uses to update state and reply to caller.

### Claude's Discretion
- GenServer state struct design (fields, defaults)
- Exact Task.async/handle_info plumbing
- Whether to use a separate internal state struct or plain map
- Error handling for Task failures and timeouts
- Test fixtures and Mox setup for GenServer tests

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Prior Phase Context
- `.planning/phases/01-core-foundation/01-CONTEXT.md` — child_spec, no auto-start, naming conventions
- `.planning/phases/03-tool-calling/03-CONTEXT.md` — ToolLoop design, Tool behaviour, execute/2 opts

### Existing Code
- `lib/phoenix_ai/tool_loop.ex` — ToolLoop.run/4 to be reused by Agent
- `lib/phoenix_ai/conversation.ex` — Conversation struct stub (id, messages, metadata)
- `lib/phoenix_ai.ex` — PhoenixAI.child_spec/1 pattern for supervision
- `lib/ai.ex` — AI.chat/2 dispatch logic (Agent follows similar pattern)
- `lib/phoenix_ai/provider.ex` — Provider behaviour contract

### OTP Patterns
- GenServer docs: https://hexdocs.pm/elixir/GenServer.html
- DynamicSupervisor docs: https://hexdocs.pm/elixir/DynamicSupervisor.html
- Task.async pattern for long-running GenServer operations

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `PhoenixAI.ToolLoop.run/4` — recursive tool execution, ready to reuse from Agent
- `PhoenixAI.Conversation` struct — stub with `id`, `messages: []`, `metadata: %{}`
- `AI.chat/2` dispatch logic — resolve provider, merge config, route to ToolLoop or direct chat
- `PhoenixAI.Config.resolve/2` — config cascade (call-site > config.exs > env vars)
- `PhoenixAI.Message` struct — canonical message with role, content, tool_calls, tool_call_id

### Established Patterns
- `child_spec/1` returns standard OTP spec (see PhoenixAI module)
- No auto-starting processes — consumers own supervision
- Provider modules resolved via `AI.provider_module/1`
- Options are keyword lists passed through the system

### Integration Points
- Agent.start_link needs to resolve provider atom → module (reuse AI.provider_module)
- Agent.prompt delegates to ToolLoop.run or provider_mod.chat
- Agent's child_spec must be compatible with DynamicSupervisor.start_child

</code_context>

<specifics>
## Specific Ideas

- The hybrid manage_history pattern mirrors Laravel/AI's Agent behavior — default managed, optionally consumer-controlled
- Task.async inside handle_call follows the OTP pattern used by Ecto, Finch, and Broadway for long-running operations
- System prompt is always prepended, never part of the accumulated history — this ensures it's always first even after reset/1
- The 60-second timeout is generous for tool loops but not infinite — consumers can override per-call

</specifics>

<deferred>
## Deferred Ideas

- **V2-02:** Named agent GenServer with `via_tuple` for long-running supervised sessions — partially addressed with `:name` opt support, but full Registry/via_tuple patterns are v2
- **V2-03:** Inline/anonymous agent helper (`PhoenixAI.prompt/2` without defining a module) — v2 convenience

</deferred>

---

*Phase: 04-agent-genserver*
*Context gathered: 2026-03-29*
