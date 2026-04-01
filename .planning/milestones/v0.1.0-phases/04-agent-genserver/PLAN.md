# Phase 4: Agent GenServer — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a stateful GenServer that owns one conversation and runs the completion-tool-call loop, with hybrid history management, Task.async for non-blocking execution, and DynamicSupervisor compatibility.

**Architecture:** A single `PhoenixAI.Agent` GenServer module using Task.async inside handle_call for long-running provider calls. Reuses `PhoenixAI.ToolLoop.run/4` for tool calling. Supports `manage_history: true` (default, accumulates) and `manage_history: false` (stateless runner).

**Tech Stack:** Elixir GenServer, Task.async, ExUnit + Mox (testing)

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `lib/phoenix_ai/agent.ex` | Create | Agent GenServer: state, start_link, prompt, get_messages, reset, child_spec |
| `test/phoenix_ai/agent_test.exs` | Create | All Agent tests: init, prompt, history, tools, busy, isolation, supervisor |

---

### Task 1: Agent GenServer — Core (start_link, init, prompt/2, handle_info)

**Files:**
- Create: `lib/phoenix_ai/agent.ex`
- Create: `test/phoenix_ai/agent_test.exs`

- [ ] **Step 1: Write core Agent tests**

Create `test/phoenix_ai/agent_test.exs`:

```elixir
defmodule PhoenixAI.AgentTest do
  use ExUnit.Case, async: false

  import Mox

  alias PhoenixAI.{Agent, Message, Response}

  setup :verify_on_exit!

  @base_opts [
    provider: PhoenixAI.MockProvider,
    api_key: "test-key",
    model: "test-model"
  ]

  describe "start_link/1" do
    test "starts agent with valid opts" do
      assert {:ok, pid} = Agent.start_link(@base_opts)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "accepts :name opt" do
      assert {:ok, pid} = Agent.start_link(@base_opts ++ [name: :test_agent])
      assert Process.alive?(pid)
      assert GenServer.whereis(:test_agent) == pid
      GenServer.stop(pid)
    end

    test "defaults manage_history to true" do
      {:ok, pid} = Agent.start_link(@base_opts)
      assert Agent.get_messages(pid) == []
      GenServer.stop(pid)
    end
  end

  describe "prompt/2 with managed history" do
    test "returns response from provider" do
      expect(PhoenixAI.MockProvider, :chat, fn messages, _opts ->
        assert [%Message{role: :user, content: "Hello"}] = messages
        {:ok, %Response{content: "Hi there!", tool_calls: [], finish_reason: "stop"}}
      end)

      {:ok, pid} = Agent.start_link(@base_opts)

      assert {:ok, %Response{content: "Hi there!"}} = Agent.prompt(pid, "Hello")

      GenServer.stop(pid)
    end

    test "prepends system prompt to messages" do
      expect(PhoenixAI.MockProvider, :chat, fn messages, _opts ->
        assert [
                 %Message{role: :system, content: "You are helpful."},
                 %Message{role: :user, content: "Hi"}
               ] = messages

        {:ok, %Response{content: "Hello!", tool_calls: [], finish_reason: "stop"}}
      end)

      {:ok, pid} = Agent.start_link(@base_opts ++ [system: "You are helpful."])

      assert {:ok, _} = Agent.prompt(pid, "Hi")

      GenServer.stop(pid)
    end

    test "accumulates messages across multiple prompts" do
      PhoenixAI.MockProvider
      |> expect(:chat, fn messages, _opts ->
        assert [%Message{role: :user, content: "My name is João"}] = messages
        {:ok, %Response{content: "Nice to meet you, João!", tool_calls: [], finish_reason: "stop"}}
      end)
      |> expect(:chat, fn messages, _opts ->
        assert [
                 %Message{role: :user, content: "My name is João"},
                 %Message{role: :assistant, content: "Nice to meet you, João!"},
                 %Message{role: :user, content: "What is my name?"}
               ] = messages

        {:ok, %Response{content: "Your name is João!", tool_calls: [], finish_reason: "stop"}}
      end)

      {:ok, pid} = Agent.start_link(@base_opts)

      assert {:ok, _} = Agent.prompt(pid, "My name is João")
      assert {:ok, %Response{content: "Your name is João!"}} = Agent.prompt(pid, "What is my name?")

      messages = Agent.get_messages(pid)
      assert length(messages) == 4

      GenServer.stop(pid)
    end

    test "propagates provider error" do
      expect(PhoenixAI.MockProvider, :chat, fn _messages, _opts ->
        {:error, %PhoenixAI.Error{status: 500, message: "Server error", provider: :mock}}
      end)

      {:ok, pid} = Agent.start_link(@base_opts)

      assert {:error, %PhoenixAI.Error{status: 500}} = Agent.prompt(pid, "Hello")

      # Messages should NOT accumulate on error
      assert Agent.get_messages(pid) == []

      GenServer.stop(pid)
    end
  end

  describe "prompt/3 with consumer-managed history" do
    test "does not accumulate messages when manage_history: false" do
      PhoenixAI.MockProvider
      |> expect(:chat, fn messages, _opts ->
        assert [%Message{role: :user, content: "Hello"}] = messages
        {:ok, %Response{content: "Hi!", tool_calls: [], finish_reason: "stop"}}
      end)
      |> expect(:chat, fn messages, _opts ->
        # No history from previous call
        assert [%Message{role: :user, content: "Again"}] = messages
        {:ok, %Response{content: "Hi again!", tool_calls: [], finish_reason: "stop"}}
      end)

      {:ok, pid} = Agent.start_link(@base_opts ++ [manage_history: false])

      assert {:ok, _} = Agent.prompt(pid, "Hello")
      assert {:ok, _} = Agent.prompt(pid, "Again")
      assert Agent.get_messages(pid) == []

      GenServer.stop(pid)
    end

    test "accepts messages: opt for consumer-managed history" do
      expect(PhoenixAI.MockProvider, :chat, fn messages, _opts ->
        assert [
                 %Message{role: :user, content: "Previous"},
                 %Message{role: :assistant, content: "I remember"},
                 %Message{role: :user, content: "Continue"}
               ] = messages

        {:ok, %Response{content: "Continuing!", tool_calls: [], finish_reason: "stop"}}
      end)

      history = [
        %Message{role: :user, content: "Previous"},
        %Message{role: :assistant, content: "I remember"}
      ]

      {:ok, pid} = Agent.start_link(@base_opts ++ [manage_history: false])

      assert {:ok, _} = Agent.prompt(pid, "Continue", messages: history)

      GenServer.stop(pid)
    end
  end

  describe "prompt/2 with tools" do
    test "delegates to ToolLoop when tools configured" do
      PhoenixAI.MockProvider
      |> expect(:format_tools, fn tools ->
        assert [PhoenixAI.TestTools.WeatherTool] = tools
        [%{"type" => "function", "function" => %{"name" => "get_weather"}}]
      end)
      |> expect(:chat, fn _messages, opts ->
        assert opts[:tools_json] != nil
        {:ok, %Response{content: "It's sunny!", tool_calls: [], finish_reason: "stop"}}
      end)

      {:ok, pid} = Agent.start_link(@base_opts ++ [tools: [PhoenixAI.TestTools.WeatherTool]])

      assert {:ok, %Response{content: "It's sunny!"}} = Agent.prompt(pid, "Weather?")

      GenServer.stop(pid)
    end
  end

  describe "get_messages/1" do
    test "returns accumulated messages" do
      expect(PhoenixAI.MockProvider, :chat, fn _messages, _opts ->
        {:ok, %Response{content: "Hi!", tool_calls: [], finish_reason: "stop"}}
      end)

      {:ok, pid} = Agent.start_link(@base_opts)
      Agent.prompt(pid, "Hello")

      messages = Agent.get_messages(pid)
      assert [%Message{role: :user, content: "Hello"}, %Message{role: :assistant, content: "Hi!"}] =
               messages

      GenServer.stop(pid)
    end

    test "returns empty list when manage_history: false" do
      {:ok, pid} = Agent.start_link(@base_opts ++ [manage_history: false])
      assert Agent.get_messages(pid) == []
      GenServer.stop(pid)
    end
  end

  describe "reset/1" do
    test "clears messages but keeps config" do
      PhoenixAI.MockProvider
      |> expect(:chat, fn _messages, _opts ->
        {:ok, %Response{content: "First", tool_calls: [], finish_reason: "stop"}}
      end)
      |> expect(:chat, fn messages, _opts ->
        # After reset, only the new user message (no history)
        assert [%Message{role: :user, content: "After reset"}] = messages
        {:ok, %Response{content: "Fresh start!", tool_calls: [], finish_reason: "stop"}}
      end)

      {:ok, pid} = Agent.start_link(@base_opts)
      Agent.prompt(pid, "Before reset")
      assert length(Agent.get_messages(pid)) == 2

      assert :ok = Agent.reset(pid)
      assert Agent.get_messages(pid) == []

      assert {:ok, %Response{content: "Fresh start!"}} = Agent.prompt(pid, "After reset")

      GenServer.stop(pid)
    end
  end

  describe "busy detection" do
    test "returns error when prompt is already in progress" do
      expect(PhoenixAI.MockProvider, :chat, fn _messages, _opts ->
        Process.sleep(200)
        {:ok, %Response{content: "Done", tool_calls: [], finish_reason: "stop"}}
      end)

      {:ok, pid} = Agent.start_link(@base_opts)

      # Start a long-running prompt in background
      task = Task.async(fn -> Agent.prompt(pid, "Slow request") end)
      Process.sleep(50)

      # Second prompt while first is running
      assert {:error, :agent_busy} = Agent.prompt(pid, "Impatient request")

      # First prompt completes normally
      assert {:ok, %Response{content: "Done"}} = Task.await(task)

      GenServer.stop(pid)
    end
  end

  describe "isolation" do
    test "killing one agent does not affect another" do
      expect(PhoenixAI.MockProvider, :chat, fn _messages, _opts ->
        {:ok, %Response{content: "Still alive!", tool_calls: [], finish_reason: "stop"}}
      end)

      {:ok, pid1} = Agent.start_link(@base_opts)
      {:ok, pid2} = Agent.start_link(@base_opts)

      Process.exit(pid1, :kill)
      Process.sleep(50)

      refute Process.alive?(pid1)
      assert Process.alive?(pid2)
      assert {:ok, %Response{content: "Still alive!"}} = Agent.prompt(pid2, "Are you there?")

      GenServer.stop(pid2)
    end
  end

  describe "DynamicSupervisor" do
    test "starts agent via DynamicSupervisor with child_spec" do
      {:ok, sup} = DynamicSupervisor.start_link(strategy: :one_for_one)

      {:ok, pid} =
        DynamicSupervisor.start_child(sup, {Agent, @base_opts})

      assert Process.alive?(pid)

      GenServer.stop(pid)
      Supervisor.stop(sup)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
mix test test/phoenix_ai/agent_test.exs
```

Expected: Compilation error — `PhoenixAI.Agent` module not found.

- [ ] **Step 3: Implement the Agent GenServer**

Create `lib/phoenix_ai/agent.ex`:

```elixir
defmodule PhoenixAI.Agent do
  @moduledoc """
  Stateful GenServer that owns one conversation and runs the completion-tool-call loop.

  ## Modes

  - **`manage_history: true`** (default) — Agent accumulates messages between `prompt/2`
    calls. The conversation grows automatically, like Laravel/AI's Agent.
  - **`manage_history: false`** — Agent is a stateless runner. Consumer passes `messages:`
    in each `prompt/3` call and manages history externally.

  ## Usage

      {:ok, pid} = PhoenixAI.Agent.start_link(
        provider: :openai,
        model: "gpt-4o",
        system: "You are a helpful assistant.",
        tools: [MyApp.Weather],
        api_key: "sk-..."
      )

      {:ok, response} = PhoenixAI.Agent.prompt(pid, "What's the weather in Lisbon?")
      response.content
      #=> "The weather in Lisbon is sunny, 22°C!"

      # Conversation continues with history
      {:ok, response} = PhoenixAI.Agent.prompt(pid, "And in Porto?")

  ## Supervision

  Start under a DynamicSupervisor:

      DynamicSupervisor.start_child(MyApp.AgentSupervisor, {PhoenixAI.Agent, opts})
  """

  use GenServer

  alias PhoenixAI.{Config, Message, Response, ToolLoop}

  @default_timeout 60_000

  defstruct [
    :provider_mod,
    :provider_atom,
    :system,
    :manage_history,
    :pending,
    :pending_user_msg,
    tools: [],
    messages: [],
    opts: []
  ]

  # --- Public API ---

  @doc "Starts an Agent GenServer. See module docs for options."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, init_opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, init_opts, gen_opts)
  end

  @doc """
  Sends a prompt to the agent and waits for the response.

  Blocks until the provider (and any tool calls) complete.
  Default timeout: 60 seconds.

  ## Options (prompt/3)

  - `:messages` — override conversation history (for `manage_history: false`)
  - `:timeout` — override call timeout in milliseconds
  """
  @spec prompt(GenServer.server(), String.t(), keyword()) ::
          {:ok, Response.t()} | {:error, term()}
  def prompt(server, text, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    GenServer.call(server, {:prompt, text, opts}, timeout)
  end

  @doc "Returns the accumulated conversation messages."
  @spec get_messages(GenServer.server()) :: [Message.t()]
  def get_messages(server) do
    GenServer.call(server, :get_messages)
  end

  @doc "Clears conversation history, keeps configuration."
  @spec reset(GenServer.server()) :: :ok
  def reset(server) do
    GenServer.call(server, :reset)
  end

  # --- GenServer Callbacks ---

  @impl GenServer
  def init(opts) do
    provider_atom = Keyword.fetch!(opts, :provider)
    provider_mod = AI.provider_module(provider_atom)
    system = Keyword.get(opts, :system)
    tools = Keyword.get(opts, :tools, [])
    manage_history = Keyword.get(opts, :manage_history, true)

    provider_opts =
      opts
      |> Keyword.drop([:provider, :system, :tools, :manage_history])
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

  @impl GenServer
  def handle_call({:prompt, _text, _msg_opts}, _from, %{pending: {_, _}} = state) do
    {:reply, {:error, :agent_busy}, state}
  end

  def handle_call({:prompt, text, msg_opts}, from, state) do
    user_msg = %Message{role: :user, content: text}
    messages = build_messages(state, user_msg, msg_opts)

    task =
      Task.async(fn ->
        if state.tools != [] do
          ToolLoop.run(state.provider_mod, messages, state.tools, state.opts)
        else
          state.provider_mod.chat(messages, state.opts)
        end
      end)

    {:noreply, %{state | pending: {from, task.ref}, pending_user_msg: user_msg}}
  end

  def handle_call(:get_messages, _from, state) do
    {:reply, state.messages, state}
  end

  def handle_call(:reset, _from, state) do
    {:reply, :ok, %{state | messages: []}}
  end

  @impl GenServer
  def handle_info({ref, result}, %{pending: {from, ref}} = state) do
    Process.demonitor(ref, [:flush])

    new_messages =
      case {state.manage_history, result} do
        {true, {:ok, %Response{} = response}} ->
          assistant_msg = %Message{
            role: :assistant,
            content: response.content,
            tool_calls: response.tool_calls
          }

          state.messages ++ [state.pending_user_msg, assistant_msg]

        _ ->
          state.messages
      end

    GenServer.reply(from, result)
    {:noreply, %{state | pending: nil, pending_user_msg: nil, messages: new_messages}}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{pending: {from, ref}} = state) do
    GenServer.reply(from, {:error, {:agent_task_failed, reason}})
    {:noreply, %{state | pending: nil, pending_user_msg: nil}}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # --- Private Helpers ---

  defp build_messages(state, user_msg, msg_opts) do
    system_msgs =
      if state.system do
        [%Message{role: :system, content: state.system}]
      else
        []
      end

    history =
      if state.manage_history do
        state.messages
      else
        Keyword.get(msg_opts, :messages, [])
      end

    system_msgs ++ history ++ [user_msg]
  end
end
```

- [ ] **Step 4: Run tests**

Run:
```bash
mix test test/phoenix_ai/agent_test.exs
```

Expected: All tests PASS.

- [ ] **Step 5: Run full test suite**

Run:
```bash
mix test
```

Expected: All tests PASS.

- [ ] **Step 6: Run formatter and credo**

Run:
```bash
mix format && mix credo
```

Expected: Clean.

- [ ] **Step 7: Commit**

```bash
git add lib/phoenix_ai/agent.ex test/phoenix_ai/agent_test.exs
git commit -m "feat(04): add Agent GenServer with Task.async and hybrid history"
```

---

### Task 2: Final Verification

- [ ] **Step 1: Run full test suite with coverage**

Run:
```bash
mix test --cover
```

Expected: All tests PASS.

- [ ] **Step 2: Run all quality checks**

Run:
```bash
mix format --check-formatted && mix credo
```

Expected: Clean.

- [ ] **Step 3: Verify success criteria**

1. ✅ `Agent.start_link(provider: ..., model: ..., system: ..., tools: [...])` starts a GenServer
2. ✅ `Agent.prompt(pid, "text")` blocks until completion and returns `{:ok, %Response{}}`
3. ✅ Crashing one agent does not affect another (isolation test)
4. ✅ Agent starts under DynamicSupervisor via `child_spec/1`
5. ✅ Conversation history accumulates across `prompt/2` calls (managed history test)
6. ✅ `manage_history: false` mode works (consumer-managed test)
7. ✅ System prompt prepended in every call
8. ✅ `get_messages/1` and `reset/1` work
9. ✅ Busy detection returns `{:error, :agent_busy}`
10. ✅ Naming via `:name` opt works

---

## Summary

| Task | Description | Commit Message |
|------|-------------|---------------|
| 1 | Agent GenServer (all functionality) | `feat(04): add Agent GenServer with Task.async and hybrid history` |
| 2 | Final verification | No commit — verification only |
