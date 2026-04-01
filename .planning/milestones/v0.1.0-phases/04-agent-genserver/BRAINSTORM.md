# Phase 4: Agent GenServer — Design Spec

**Date:** 2026-03-29
**Phase:** 04-agent-genserver
**Status:** Approved
**Approach:** A — GenServer + Task.async, bottom-up

## Overview

A stateful GenServer that owns one conversation's state and runs the completion-tool-call loop. Supports managed and consumer-managed history modes. Uses Task.async for long-running provider calls (OTP best practice). Supervisable via DynamicSupervisor. Supports optional naming.

**Requirements covered:** AGENT-01, AGENT-02, AGENT-03, AGENT-04, AGENT-05

## Architecture

### Component Diagram

```
PhoenixAI.Agent (GenServer)
├── State: provider_mod, system, tools, messages, opts, manage_history, pending
├── start_link/1 → init/1 (resolve provider, merge config)
├── prompt/2,3 → handle_call → Task.async(ToolLoop.run or provider.chat)
│   └── handle_info({ref, result}) → accumulate messages → GenServer.reply
├── get_messages/1 → handle_call → reply with state.messages
├── reset/1 → handle_call → clear messages
└── child_spec/1 → standard OTP spec for DynamicSupervisor
```

### Data Flow (prompt/2 with manage_history: true)

```
caller
  → GenServer.call(pid, {:prompt, "Weather?", []}, 60_000)
  → handle_call:
      1. Build messages: [system_msg] ++ state.messages ++ [user_msg]
      2. Spawn Task.async → ToolLoop.run(provider_mod, messages, tools, opts)
      3. Return {:noreply, %{state | pending: {from, task_ref}}}
  → Task completes:
      handle_info({ref, {:ok, %Response{}}})
      4. Accumulate: state.messages ++ [user_msg, ...intermediate..., assistant_msg]
      5. GenServer.reply(from, {:ok, response})
  → caller receives {:ok, %Response{content: "It's sunny!"}}
```

## Components

### 1. Agent State

```elixir
defmodule PhoenixAI.Agent do
  use GenServer

  defstruct [
    :provider_mod,
    :provider_atom,
    :system,
    :manage_history,
    :pending,
    tools: [],
    messages: [],
    opts: []
  ]
end
```

| Field | Type | Description |
|-------|------|-------------|
| `provider_mod` | module | Resolved provider module (e.g., `PhoenixAI.Providers.OpenAI`) |
| `provider_atom` | atom | Original provider atom (e.g., `:openai`) |
| `system` | String.t \| nil | System prompt, immutable after init |
| `manage_history` | boolean | `true` (default): accumulate messages. `false`: stateless runner |
| `pending` | {from, ref} \| nil | Tracks in-flight Task for busy detection |
| `tools` | [module] | Tool modules implementing PhoenixAI.Tool |
| `messages` | [Message.t] | Accumulated conversation history |
| `opts` | keyword | Provider opts (api_key, model, temperature, etc.) |

### 2. Public API

**start_link/1:**

```elixir
@spec start_link(keyword()) :: GenServer.on_start()
def start_link(opts)
```

Accepts: `provider:`, `model:`, `system:`, `tools:`, `manage_history:` (default `true`), `name:`, and any provider opts (`api_key:`, `temperature:`, etc.).

Resolves provider atom → module via `AI.provider_module/1`. Merges config via `Config.resolve/2`. Strips Agent-specific keys from provider opts.

If `:name` is provided, passes it to `GenServer.start_link/3` options.

**prompt/2 and prompt/3:**

```elixir
@spec prompt(GenServer.server(), String.t(), keyword()) ::
        {:ok, Response.t()} | {:error, term()}
def prompt(server, text, opts \\ [])
```

Synchronous from caller's perspective (uses `GenServer.call` with timeout). Internally non-blocking (Task.async pattern).

`opts` for prompt/3:
- `messages:` — override messages (for `manage_history: false` mode)
- `timeout:` — override call timeout (default 60_000ms)

**get_messages/1:**

```elixir
@spec get_messages(GenServer.server()) :: [Message.t()]
def get_messages(server)
```

Returns accumulated messages. Returns `[]` if `manage_history: false`.

**reset/1:**

```elixir
@spec reset(GenServer.server()) :: :ok
def reset(server)
```

Clears message history, keeps config. No-op if `manage_history: false`.

**child_spec/1:**

```elixir
@spec child_spec(keyword()) :: Supervisor.child_spec()
def child_spec(opts)
```

Standard OTP child_spec. Compatible with `DynamicSupervisor.start_child/2`.

### 3. GenServer Callbacks

**init/1:**

```elixir
def init(opts) do
  provider_atom = Keyword.fetch!(opts, :provider)
  provider_mod = AI.provider_module(provider_atom)
  system = Keyword.get(opts, :system)
  tools = Keyword.get(opts, :tools, [])
  manage_history = Keyword.get(opts, :manage_history, true)

  provider_opts =
    opts
    |> Keyword.drop([:provider, :system, :tools, :manage_history, :name])
    |> then(&Config.resolve(provider_atom, &1))

  state = %__MODULE__{
    provider_mod: provider_mod,
    provider_atom: provider_atom,
    system: system,
    tools: tools,
    manage_history: manage_history,
    opts: provider_opts
  }

  {:ok, state}
end
```

**handle_call({:prompt, text, msg_opts}, from, state):**

1. If `state.pending != nil` → `{:reply, {:error, :agent_busy}, state}`
2. Build messages:
   - System message (if present): `[%Message{role: :system, content: state.system}]`
   - History: `state.messages` (if manage_history: true) or `msg_opts[:messages]` (if consumer passes them) or `[]` (if manage_history: false and no messages passed — just system + user msg)
   - New user message: `[%Message{role: :user, content: text}]`
3. Spawn Task:
   ```elixir
   task = Task.async(fn ->
     if state.tools != [] do
       ToolLoop.run(state.provider_mod, messages, state.tools, state.opts)
     else
       state.provider_mod.chat(messages, state.opts)
     end
   end)
   ```
4. Return `{:noreply, %{state | pending: {from, task.ref}}}`

**handle_info({ref, result}, state) — Task completion:**

1. `Process.demonitor(ref, [:flush])`
2. If `manage_history: true` and result is `{:ok, response}`:
   - Reconstruct what happened: user_msg + (ToolLoop intermediate messages are NOT available from the response — only the final response)
   - Accumulate: `state.messages ++ [user_msg, %Message{role: :assistant, content: response.content, tool_calls: response.tool_calls}]`
3. `GenServer.reply(from, result)`
4. Return `{:noreply, %{state | pending: nil, messages: new_messages}}`

**Important note on history accumulation:** The ToolLoop returns only the final `%Response{}`, not the intermediate messages (tool calls, tool results). For `manage_history: true`, the Agent only accumulates the user message and the final assistant response. The intermediate tool call messages are handled internally by ToolLoop during its execution but are NOT preserved in the Agent's history.

This is intentional and matches the Laravel/AI pattern — the conversation history shows "user asked → assistant answered", not the internal tool calling details. If consumers need the full trace, they can use `manage_history: false` and manage messages themselves, passing the full history from ToolLoop's perspective.

**handle_info({:DOWN, ref, :process, _pid, reason}, state) — Task crash:**

1. If `ref` matches `state.pending` ref:
   - `GenServer.reply(from, {:error, {:agent_task_failed, reason}})`
   - Return `{:noreply, %{state | pending: nil}}`

**handle_call(:get_messages, _from, state):**

Return `{:reply, state.messages, state}`

**handle_call(:reset, _from, state):**

Return `{:reply, :ok, %{state | messages: []}}`

### 4. Naming Support

```elixir
def start_link(opts) do
  {name, init_opts} = Keyword.pop(opts, :name)
  gen_opts = if name, do: [name: name], else: []
  GenServer.start_link(__MODULE__, init_opts, gen_opts)
end
```

Usage:

```elixir
# By PID
{:ok, pid} = PhoenixAI.Agent.start_link(provider: :openai)
PhoenixAI.Agent.prompt(pid, "Hello")

# By name
PhoenixAI.Agent.start_link(provider: :openai, name: :my_agent)
PhoenixAI.Agent.prompt(:my_agent, "Hello")

# With Registry
PhoenixAI.Agent.start_link(provider: :openai, name: {:via, Registry, {MyReg, "agent-1"}})
```

### 5. Error Handling

| Scenario | Behavior |
|----------|----------|
| Prompt while busy | `{:error, :agent_busy}` — immediate reply, no Task spawned |
| Provider/ToolLoop error | `{:error, reason}` propagated from ToolLoop or provider |
| Task crash | `{:error, {:agent_task_failed, reason}}` via handle_info :DOWN |
| Caller timeout | Caller gets exit, Task continues but result discarded on next handle_info |
| Missing API key | `{:error, {:missing_api_key, atom}}` from init or provider call |
| Invalid provider | Error in init — GenServer fails to start |

## Testing Strategy

### Unit Tests (`test/phoenix_ai/agent_test.exs`)

1. **Init & start_link:**
   - Starts with valid opts
   - Resolves provider atom → module
   - Accepts `:name` opt
   - Defaults manage_history to true

2. **prompt/2 with managed history:**
   - Mock provider returns response → Agent returns {:ok, response}
   - Messages accumulate across multiple prompt calls
   - System prompt prepended in every provider call

3. **prompt/3 with consumer-managed history:**
   - manage_history: false, consumer passes messages: in opts
   - Agent does not accumulate messages

4. **prompt/2 with tools:**
   - Mock provider format_tools + chat sequence
   - ToolLoop runs, Agent returns final response

5. **get_messages/1:**
   - Returns accumulated messages
   - Returns [] when manage_history: false

6. **reset/1:**
   - Clears messages, keeps config
   - Next prompt starts fresh conversation

7. **Busy detection:**
   - Start long-running prompt (mock with Process.sleep)
   - Second prompt returns {:error, :agent_busy}

8. **Isolation:**
   - Start 2 agents, kill one via Process.exit
   - Other agent still responds to prompt

9. **DynamicSupervisor:**
   - Start agent via DynamicSupervisor.start_child with child_spec

## Files Changed

| File | Action | Description |
|------|--------|-------------|
| `lib/phoenix_ai/agent.ex` | Create | Agent GenServer with Task.async pattern |
| `test/phoenix_ai/agent_test.exs` | Create | Agent unit tests with Mox |

**No changes to:** `lib/ai.ex`, `lib/phoenix_ai/tool_loop.ex`, provider adapters

## Success Criteria (from ROADMAP.md)

1. `PhoenixAI.Agent.start_link(provider: ..., model: ..., system: ..., tools: [...])` starts a GenServer that accepts prompts
2. `PhoenixAI.Agent.prompt(pid, "text")` blocks until the full completion-tool-call loop finishes and returns `{:ok, %Response{}}`
3. Crashing one agent process does not affect any other running agent process
4. The agent can be started under a DynamicSupervisor using its `child_spec/1`
5. Conversation history accumulates correctly across multiple `prompt/2` calls

---

*Design approved: 2026-03-29*
*Approach: A — GenServer + Task.async, bottom-up*
