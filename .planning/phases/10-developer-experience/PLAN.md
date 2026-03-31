# Phase 10: Developer Experience — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make PhoenixAI testable offline, instrumented with telemetry, validated with NimbleOptions, documented with ExDoc guides + cookbook, and ready for Hex publish.

**Architecture:** Incremental layering — each deliverable is additive over existing code, no logic rewrites. TestProvider → Telemetry → NimbleOptions → ExDoc & Hex. Each layer builds on the previous.

**Tech Stack:** Elixir, `:telemetry`, `NimbleOptions`, `ExDoc`, `Hex`

---

## File Map

### New Files
| File | Responsibility |
|---|---|
| `lib/phoenix_ai/providers/test_provider.ex` | Provider behaviour impl with Agent-based state per test PID |
| `lib/phoenix_ai/test.ex` | ExUnit helper macros: `use PhoenixAI.Test`, `set_responses/1`, `set_handler/1`, `assert_called/1` |
| `test/phoenix_ai/providers/test_provider_test.exs` | TestProvider queue, handler, stream, isolation tests |
| `test/phoenix_ai/telemetry_test.exs` | Telemetry span and discrete event tests |
| `test/phoenix_ai/nimble_options_test.exs` | NimbleOptions validation tests for all public APIs |
| `guides/getting-started.md` | Install, configure, first AI.chat call |
| `guides/provider-setup.md` | Per-provider config, TestProvider, config cascade |
| `guides/agents-and-tools.md` | Agent GenServer, Tool behaviour, tool loop |
| `guides/pipelines-and-teams.md` | Pipeline DSL, Team DSL, composition |
| `guides/cookbook/rag-pipeline.md` | RAG pattern using Pipeline |
| `guides/cookbook/multi-agent-team.md` | Parallel agents with Team |
| `guides/cookbook/streaming-liveview.md` | Stream to LiveView via `to: pid` |
| `guides/cookbook/custom-tools.md` | Building Tool modules |

### Modified Files
| File | Changes |
|---|---|
| `lib/ai.ex` | Add `:test` to providers, telemetry spans, NimbleOptions validation |
| `lib/phoenix_ai/agent.ex` | NimbleOptions validation in start_link (Agent prompt telemetry is covered by the underlying AI.chat span) |
| `lib/phoenix_ai/tool_loop.ex` | Telemetry events for tool execution |
| `lib/phoenix_ai/pipeline.ex` | Telemetry events for steps |
| `lib/phoenix_ai/team.ex` | Telemetry event for completion |
| `mix.exs` | Update docs config, add files to package |

---

## Task 1: TestProvider — Core Module

**Files:**
- Create: `lib/phoenix_ai/providers/test_provider.ex`
- Test: `test/phoenix_ai/providers/test_provider_test.exs`

- [ ] **Step 1: Write the failing test — queue mode**

```elixir
# test/phoenix_ai/providers/test_provider_test.exs
defmodule PhoenixAI.Providers.TestProviderTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Providers.TestProvider
  alias PhoenixAI.Response

  describe "queue mode" do
    test "returns responses in FIFO order" do
      {:ok, _} = TestProvider.start_state(self())

      TestProvider.put_responses(self(), [
        {:ok, %Response{content: "first", usage: %{total_tokens: 5}}},
        {:ok, %Response{content: "second", usage: %{total_tokens: 10}}}
      ])

      assert {:ok, %Response{content: "first"}} = TestProvider.chat([], api_key: "test")
      assert {:ok, %Response{content: "second"}} = TestProvider.chat([], api_key: "test")
    end

    test "returns error when queue is exhausted" do
      {:ok, _} = TestProvider.start_state(self())
      TestProvider.put_responses(self(), [{:ok, %Response{content: "only"}}])

      assert {:ok, %Response{content: "only"}} = TestProvider.chat([], api_key: "test")
      assert {:error, :no_more_responses} = TestProvider.chat([], api_key: "test")
    end

    test "returns error when not configured" do
      assert {:error, :test_provider_not_configured} = TestProvider.chat([], api_key: "test")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/phoenix_ai/providers/test_provider_test.exs`
Expected: FAIL — `TestProvider` module does not exist

- [ ] **Step 3: Implement TestProvider core**

```elixir
# lib/phoenix_ai/providers/test_provider.ex
defmodule PhoenixAI.Providers.TestProvider do
  @moduledoc """
  Test provider for offline testing. Returns scripted responses without network calls.

  Supports two modes:
  - **Queue (FIFO):** Pre-defined responses consumed in order
  - **Handler:** Custom function receives messages and opts

  State is per-process (keyed by PID) for async test isolation.

  ## Usage

      # In your test
      use PhoenixAI.Test

      setup do
        set_responses([{:ok, %Response{content: "Hello"}}])
      end

      test "works offline" do
        assert {:ok, %Response{content: "Hello"}} =
          AI.chat([%Message{role: :user, content: "Hi"}], provider: :test)
      end
  """

  @behaviour PhoenixAI.Provider

  alias PhoenixAI.{Response, StreamChunk}

  # --- State Management ---

  @doc false
  def start_state(pid) do
    name = via(pid)

    case Agent.start_link(fn -> %{responses: [], handler: nil, calls: []} end, name: name) do
      {:ok, agent_pid} -> {:ok, agent_pid}
      {:error, {:already_started, agent_pid}} -> {:ok, agent_pid}
    end
  end

  @doc false
  def stop_state(pid) do
    name = via(pid)

    case GenServer.whereis(name) do
      nil -> :ok
      agent_pid -> Agent.stop(agent_pid)
    end
  end

  @doc false
  def put_responses(pid, responses) when is_list(responses) do
    Agent.update(via(pid), fn state ->
      %{state | responses: state.responses ++ responses}
    end)
  end

  @doc false
  def put_handler(pid, handler) when is_function(handler, 2) do
    Agent.update(via(pid), fn state ->
      %{state | handler: handler}
    end)
  end

  @doc false
  def get_calls(pid) do
    Agent.get(via(pid), fn state -> state.calls end)
  end

  defp via(pid) do
    {:via, Registry, {PhoenixAI.TestRegistry, pid}}
  end

  defp get_state(pid) do
    case GenServer.whereis(via(pid)) do
      nil -> nil
      _agent -> Agent.get(via(pid), & &1)
    end
  end

  defp record_call(pid, messages, opts) do
    Agent.update(via(pid), fn state ->
      %{state | calls: state.calls ++ [{messages, opts}]}
    end)
  end

  # --- Provider Behaviour ---

  @impl PhoenixAI.Provider
  def chat(messages, opts) do
    caller = self()

    case get_state(caller) do
      nil ->
        {:error, :test_provider_not_configured}

      %{handler: handler} when is_function(handler, 2) ->
        record_call(caller, messages, opts)
        handler.(messages, opts)

      %{responses: []} ->
        {:error, :no_more_responses}

      %{responses: [response | _rest]} ->
        record_call(caller, messages, opts)

        Agent.update(via(caller), fn state ->
          %{state | responses: tl(state.responses)}
        end)

        response
    end
  end

  @impl PhoenixAI.Provider
  def parse_response(body), do: body

  @impl PhoenixAI.Provider
  def format_tools(tools), do: Enum.map(tools, fn mod -> %{"name" => mod.name()} end)

  @impl PhoenixAI.Provider
  def stream(messages, callback, opts) do
    case chat(messages, opts) do
      {:ok, %Response{content: content} = response} ->
        # Emit synthetic chunks character by character
        content
        |> String.graphemes()
        |> Enum.each(fn char ->
          callback.(%StreamChunk{delta: char})
        end)

        callback.(%StreamChunk{finish_reason: "stop", usage: response.usage})
        {:ok, response}

      error ->
        error
    end
  end

  @impl PhoenixAI.Provider
  def parse_chunk(%{data: data}), do: %StreamChunk{delta: data}
end
```

- [ ] **Step 4: Start the TestRegistry**

The TestProvider uses a `Registry` for per-PID Agent lookup. We need it available in test env. Add to `test/test_helper.exs`:

Read `test/test_helper.exs` first, then prepend:

```elixir
{:ok, _} = Registry.start_link(keys: :unique, name: PhoenixAI.TestRegistry)
```

before the existing `ExUnit.start()` call.

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test test/phoenix_ai/providers/test_provider_test.exs`
Expected: 3 tests, 0 failures

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_ai/providers/test_provider.ex test/phoenix_ai/providers/test_provider_test.exs test/test_helper.exs
git commit -m "feat(10): add TestProvider with queue mode and per-PID state"
```

---

## Task 2: TestProvider — Handler Mode & Call Log

**Files:**
- Modify: `lib/phoenix_ai/providers/test_provider.ex`
- Modify: `test/phoenix_ai/providers/test_provider_test.exs`

- [ ] **Step 1: Write failing tests — handler mode and call log**

Append to `test/phoenix_ai/providers/test_provider_test.exs`:

```elixir
  describe "handler mode" do
    test "calls handler with messages and opts" do
      {:ok, _} = TestProvider.start_state(self())

      TestProvider.put_handler(self(), fn messages, opts ->
        last = List.last(messages)
        {:ok, %Response{content: "Echo: #{last.content}", usage: %{total_tokens: length(messages)}}}
      end)

      messages = [%PhoenixAI.Message{role: :user, content: "Hello"}]
      assert {:ok, %Response{content: "Echo: Hello"}} = TestProvider.chat(messages, api_key: "test")
    end

    test "handler takes precedence over queue" do
      {:ok, _} = TestProvider.start_state(self())

      TestProvider.put_responses(self(), [{:ok, %Response{content: "from queue"}}])
      TestProvider.put_handler(self(), fn _msgs, _opts ->
        {:ok, %Response{content: "from handler"}}
      end)

      assert {:ok, %Response{content: "from handler"}} = TestProvider.chat([], api_key: "test")
    end
  end

  describe "call log" do
    test "records messages and opts for each call" do
      {:ok, _} = TestProvider.start_state(self())

      TestProvider.put_responses(self(), [
        {:ok, %Response{content: "r1"}},
        {:ok, %Response{content: "r2"}}
      ])

      msgs1 = [%PhoenixAI.Message{role: :user, content: "first"}]
      msgs2 = [%PhoenixAI.Message{role: :user, content: "second"}]

      TestProvider.chat(msgs1, api_key: "k1")
      TestProvider.chat(msgs2, api_key: "k2")

      calls = TestProvider.get_calls(self())
      assert length(calls) == 2
      assert {^msgs1, [api_key: "k1"]} = Enum.at(calls, 0)
      assert {^msgs2, [api_key: "k2"]} = Enum.at(calls, 1)
    end
  end
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `mix test test/phoenix_ai/providers/test_provider_test.exs`
Expected: 6 tests, 0 failures (handler, precedence, and call log should pass with existing implementation)

- [ ] **Step 3: Commit**

```bash
git add test/phoenix_ai/providers/test_provider_test.exs
git commit -m "test(10): add handler mode and call log tests for TestProvider"
```

---

## Task 3: TestProvider — Stream Support & Async Isolation

**Files:**
- Modify: `test/phoenix_ai/providers/test_provider_test.exs`

- [ ] **Step 1: Write tests — stream and async isolation**

Append to `test/phoenix_ai/providers/test_provider_test.exs`:

```elixir
  describe "stream/3" do
    test "emits synthetic chunks from scripted response" do
      {:ok, _} = TestProvider.start_state(self())

      TestProvider.put_responses(self(), [
        {:ok, %Response{content: "Hi", usage: %{total_tokens: 2}}}
      ])

      chunks = []
      test_pid = self()

      callback = fn chunk ->
        send(test_pid, {:chunk, chunk})
      end

      assert {:ok, %Response{content: "Hi"}} = TestProvider.stream([], callback, api_key: "test")

      assert_received {:chunk, %StreamChunk{delta: "H"}}
      assert_received {:chunk, %StreamChunk{delta: "i"}}
      assert_received {:chunk, %StreamChunk{finish_reason: "stop"}}
    end
  end

  describe "async isolation" do
    test "two concurrent processes have independent state" do
      parent = self()

      task1 =
        Task.async(fn ->
          {:ok, _} = TestProvider.start_state(self())
          TestProvider.put_responses(self(), [{:ok, %Response{content: "task1"}}])
          result = TestProvider.chat([], api_key: "test")
          TestProvider.stop_state(self())
          result
        end)

      task2 =
        Task.async(fn ->
          {:ok, _} = TestProvider.start_state(self())
          TestProvider.put_responses(self(), [{:ok, %Response{content: "task2"}}])
          result = TestProvider.chat([], api_key: "test")
          TestProvider.stop_state(self())
          result
        end)

      assert {:ok, %Response{content: "task1"}} = Task.await(task1)
      assert {:ok, %Response{content: "task2"}} = Task.await(task2)
    end
  end
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `mix test test/phoenix_ai/providers/test_provider_test.exs`
Expected: 8 tests, 0 failures

- [ ] **Step 3: Commit**

```bash
git add test/phoenix_ai/providers/test_provider_test.exs
git commit -m "test(10): add stream and async isolation tests for TestProvider"
```

---

## Task 4: PhoenixAI.Test ExUnit Helper & AI Dispatch

**Files:**
- Create: `lib/phoenix_ai/test.ex`
- Modify: `lib/ai.ex`
- Test: `test/phoenix_ai/test_helper_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
# test/phoenix_ai/test_helper_test.exs
defmodule PhoenixAI.TestHelperTest do
  use ExUnit.Case, async: true
  use PhoenixAI.Test

  alias PhoenixAI.{Message, Response}

  describe "use PhoenixAI.Test" do
    test "set_responses/1 + AI.chat with provider: :test" do
      set_responses([
        {:ok, %Response{content: "Hello from test!", usage: %{total_tokens: 5}}}
      ])

      assert {:ok, %Response{content: "Hello from test!"}} =
               AI.chat([%Message{role: :user, content: "Hi"}], provider: :test, api_key: "test")
    end

    test "set_handler/1 + AI.chat with provider: :test" do
      set_handler(fn messages, _opts ->
        last = List.last(messages)
        {:ok, %Response{content: "Echo: #{last.content}"}}
      end)

      assert {:ok, %Response{content: "Echo: Hey"}} =
               AI.chat([%Message{role: :user, content: "Hey"}], provider: :test, api_key: "test")
    end

    test "assert_called/0 returns call log" do
      set_responses([{:ok, %Response{content: "ok"}}])

      msgs = [%Message{role: :user, content: "test"}]
      AI.chat(msgs, provider: :test, api_key: "test")

      calls = get_calls()
      assert length(calls) == 1
      assert {^msgs, _opts} = hd(calls)
    end

    test "state is cleaned up after test" do
      # This test verifies that on_exit cleanup works.
      # If previous tests leaked state, this would see stale responses.
      alias PhoenixAI.Providers.TestProvider
      assert {:error, :test_provider_not_configured} = TestProvider.chat([], api_key: "test")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/phoenix_ai/test_helper_test.exs`
Expected: FAIL — `PhoenixAI.Test` module does not exist

- [ ] **Step 3: Create PhoenixAI.Test helper module**

```elixir
# lib/phoenix_ai/test.ex
defmodule PhoenixAI.Test do
  @moduledoc """
  ExUnit helper for testing with PhoenixAI's TestProvider.

  ## Usage

      defmodule MyTest do
        use ExUnit.Case, async: true
        use PhoenixAI.Test

        test "chat returns scripted response" do
          set_responses([{:ok, %Response{content: "Hello"}}])

          assert {:ok, %Response{content: "Hello"}} =
            AI.chat([%Message{role: :user, content: "Hi"}], provider: :test, api_key: "test")
        end
      end
  """

  defmacro __using__(_opts) do
    quote do
      alias PhoenixAI.Providers.TestProvider

      setup do
        {:ok, _} = TestProvider.start_state(self())
        on_exit(fn -> TestProvider.stop_state(self()) end)
        :ok
      end

      @doc false
      def set_responses(responses) do
        TestProvider.put_responses(self(), responses)
      end

      @doc false
      def set_handler(handler) do
        TestProvider.put_handler(self(), handler)
      end

      @doc false
      def get_calls do
        TestProvider.get_calls(self())
      end
    end
  end
end
```

- [ ] **Step 4: Add `:test` to AI dispatch**

In `lib/ai.ex`, add `:test` to `@known_providers` and add a clause to `provider_module/1`:

Change:
```elixir
@known_providers [:openai, :anthropic, :openrouter]
```
to:
```elixir
@known_providers [:openai, :anthropic, :openrouter, :test]
```

Add clause:
```elixir
def provider_module(:test), do: PhoenixAI.Providers.TestProvider
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test test/phoenix_ai/test_helper_test.exs`
Expected: 4 tests, 0 failures

Then run full suite:

Run: `mix test`
Expected: All existing tests still pass

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_ai/test.ex lib/ai.ex test/phoenix_ai/test_helper_test.exs
git commit -m "feat(10): add PhoenixAI.Test helper and :test provider dispatch"
```

---

## Task 5: Telemetry — Chat & Stream Spans

**Files:**
- Modify: `lib/ai.ex`
- Create: `test/phoenix_ai/telemetry_test.exs`

- [ ] **Step 1: Write the failing test — chat telemetry**

```elixir
# test/phoenix_ai/telemetry_test.exs
defmodule PhoenixAI.TelemetryTest do
  use ExUnit.Case, async: true
  use PhoenixAI.Test

  alias PhoenixAI.{Message, Response}

  describe "AI.chat/2 telemetry" do
    test "emits [:phoenix_ai, :chat, :start] and [:phoenix_ai, :chat, :stop]" do
      test_pid = self()
      ref = make_ref()

      :telemetry.attach_many(
        "test-chat-#{inspect(ref)}",
        [
          [:phoenix_ai, :chat, :start],
          [:phoenix_ai, :chat, :stop]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      set_responses([{:ok, %Response{content: "hi", usage: %{total_tokens: 5}}}])

      AI.chat([%Message{role: :user, content: "hello"}], provider: :test, api_key: "test")

      assert_received {:telemetry, [:phoenix_ai, :chat, :start], %{system_time: _},
                       %{provider: :test}}

      assert_received {:telemetry, [:phoenix_ai, :chat, :stop], %{duration: _},
                       %{provider: :test, status: :ok}}

      :telemetry.detach("test-chat-#{inspect(ref)}")
    end

    test "emits [:phoenix_ai, :chat, :exception] on error" do
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test-chat-exc-#{inspect(ref)}",
        [:phoenix_ai, :chat, :exception],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      # No responses set — will fail with :test_provider_not_configured
      # But the error is returned, not raised, so no exception event.
      # Instead test with a handler that raises.
      set_handler(fn _, _ -> raise "boom" end)

      catch_exit do
        AI.chat([%Message{role: :user, content: "hello"}], provider: :test, api_key: "test")
      end

      assert_received {:telemetry, [:phoenix_ai, :chat, :exception], %{duration: _}, %{}}

      :telemetry.detach("test-chat-exc-#{inspect(ref)}")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/phoenix_ai/telemetry_test.exs`
Expected: FAIL — no telemetry events emitted

- [ ] **Step 3: Instrument AI.chat/2 with telemetry span**

In `lib/ai.ex`, refactor `chat/2` to wrap with `:telemetry.span/3`:

```elixir
  def chat(messages, opts \\ []) do
    provider_atom = opts[:provider] || default_provider()
    meta = %{provider: provider_atom, model: opts[:model]}

    :telemetry.span([:phoenix_ai, :chat], meta, fn ->
      case resolve_provider(provider_atom) do
        {:ok, provider_mod} ->
          merged_opts = Config.resolve(provider_atom, Keyword.delete(opts, :provider))
          result = dispatch(provider_mod, messages, merged_opts, provider_atom)
          stop_meta = Map.merge(meta, telemetry_stop_meta(result))
          {result, stop_meta}

        {:error, _} = error ->
          {error, Map.put(meta, :status, :error)}
      end
    end)
  end

  defp telemetry_stop_meta({:ok, %Response{usage: usage}}) do
    %{status: :ok, usage: usage || %{}}
  end

  defp telemetry_stop_meta({:error, _}) do
    %{status: :error}
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/phoenix_ai/telemetry_test.exs`
Expected: 2 tests, 0 failures

- [ ] **Step 5: Write the failing test — stream telemetry**

Append to `test/phoenix_ai/telemetry_test.exs`:

```elixir
  describe "AI.stream/2 telemetry" do
    test "emits [:phoenix_ai, :stream, :start] and [:phoenix_ai, :stream, :stop]" do
      test_pid = self()
      ref = make_ref()

      :telemetry.attach_many(
        "test-stream-#{inspect(ref)}",
        [
          [:phoenix_ai, :stream, :start],
          [:phoenix_ai, :stream, :stop]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      set_responses([{:ok, %Response{content: "hi", usage: %{total_tokens: 3}}}])

      AI.stream([%Message{role: :user, content: "hello"}],
        provider: :test,
        api_key: "test",
        on_chunk: fn _chunk -> :ok end
      )

      assert_received {:telemetry, [:phoenix_ai, :stream, :start], %{system_time: _},
                       %{provider: :test}}

      assert_received {:telemetry, [:phoenix_ai, :stream, :stop], %{duration: _},
                       %{provider: :test, status: :ok}}

      :telemetry.detach("test-stream-#{inspect(ref)}")
    end
  end
```

- [ ] **Step 6: Instrument AI.stream/2 with telemetry span**

In `lib/ai.ex`, refactor `stream/2` similarly:

```elixir
  def stream(messages, opts \\ []) do
    provider_atom = opts[:provider] || default_provider()
    meta = %{provider: provider_atom, model: opts[:model]}

    :telemetry.span([:phoenix_ai, :stream], meta, fn ->
      case resolve_provider(provider_atom) do
        {:ok, provider_mod} ->
          merged_opts = Config.resolve(provider_atom, Keyword.delete(opts, :provider))
          result = dispatch_stream(provider_mod, messages, merged_opts, provider_atom)
          stop_meta = Map.merge(meta, telemetry_stop_meta(result))
          {result, stop_meta}

        {:error, _} = error ->
          {error, Map.put(meta, :status, :error)}
      end
    end)
  end
```

- [ ] **Step 7: Run all telemetry tests**

Run: `mix test test/phoenix_ai/telemetry_test.exs`
Expected: 3 tests, 0 failures

- [ ] **Step 8: Run full suite**

Run: `mix test`
Expected: All tests pass

- [ ] **Step 9: Commit**

```bash
git add lib/ai.ex test/phoenix_ai/telemetry_test.exs
git commit -m "feat(10): add telemetry spans for AI.chat/2 and AI.stream/2"
```

---

## Task 6: Telemetry — Tool Call Events

**Files:**
- Modify: `lib/phoenix_ai/tool_loop.ex`
- Modify: `test/phoenix_ai/telemetry_test.exs`

- [ ] **Step 1: Write the failing test**

Append to `test/phoenix_ai/telemetry_test.exs`:

```elixir
  describe "tool call telemetry" do
    test "emits [:phoenix_ai, :tool_call, :start] and [:phoenix_ai, :tool_call, :stop]" do
      test_pid = self()
      ref = make_ref()

      :telemetry.attach_many(
        "test-tool-#{inspect(ref)}",
        [
          [:phoenix_ai, :tool_call, :start],
          [:phoenix_ai, :tool_call, :stop]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      tool_call = %PhoenixAI.ToolCall{id: "tc1", name: "get_weather", arguments: %{"city" => "Lisbon"}}
      tools = [PhoenixAI.TestTools.WeatherTool]

      # execute_and_build_results is public
      PhoenixAI.ToolLoop.execute_and_build_results([tool_call], tools, [])

      assert_received {:telemetry, [:phoenix_ai, :tool_call, :start], %{},
                       %{tool: "get_weather"}}

      assert_received {:telemetry, [:phoenix_ai, :tool_call, :stop], %{duration: _},
                       %{tool: "get_weather", status: :ok}}

      :telemetry.detach("test-tool-#{inspect(ref)}")
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/phoenix_ai/telemetry_test.exs --only describe:"tool call telemetry"`
Expected: FAIL — no telemetry events emitted

- [ ] **Step 3: Add telemetry to ToolLoop.execute_tool/3**

In `lib/phoenix_ai/tool_loop.ex`, modify the private `execute_tool/3` function:

```elixir
  defp execute_tool(%ToolCall{} = tool_call, tools, opts) do
    :telemetry.execute([:phoenix_ai, :tool_call, :start], %{}, %{tool: tool_call.name})
    start_time = System.monotonic_time()

    result =
      case find_tool(tools, tool_call.name) do
        nil ->
          %ToolResult{tool_call_id: tool_call.id, error: "Unknown tool: #{tool_call.name}"}

        mod ->
          try do
            case mod.execute(tool_call.arguments, opts) do
              {:ok, result} ->
                %ToolResult{tool_call_id: tool_call.id, content: result}

              {:error, reason} ->
                %ToolResult{tool_call_id: tool_call.id, error: to_string(reason)}
            end
          rescue
            e ->
              %ToolResult{tool_call_id: tool_call.id, error: Exception.message(e)}
          end
      end

    duration = System.monotonic_time() - start_time
    status = if result.error, do: :error, else: :ok
    :telemetry.execute([:phoenix_ai, :tool_call, :stop], %{duration: duration}, %{tool: tool_call.name, status: status})

    result
  end
```

- [ ] **Step 4: Run tests**

Run: `mix test test/phoenix_ai/telemetry_test.exs`
Expected: 4 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_ai/tool_loop.ex test/phoenix_ai/telemetry_test.exs
git commit -m "feat(10): add telemetry events for tool call execution"
```

---

## Task 7: Telemetry — Pipeline Step & Team Complete Events

**Files:**
- Modify: `lib/phoenix_ai/pipeline.ex`
- Modify: `lib/phoenix_ai/team.ex`
- Modify: `test/phoenix_ai/telemetry_test.exs`

- [ ] **Step 1: Write failing tests — pipeline and team telemetry**

Append to `test/phoenix_ai/telemetry_test.exs`:

```elixir
  describe "pipeline step telemetry" do
    test "emits [:phoenix_ai, :pipeline, :step] for each step" do
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test-pipeline-#{inspect(ref)}",
        [:phoenix_ai, :pipeline, :step],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      steps = [
        fn input -> {:ok, input <> " a"} end,
        fn input -> {:ok, input <> " b"} end
      ]

      PhoenixAI.Pipeline.run(steps, "start")

      assert_received {:telemetry, [:phoenix_ai, :pipeline, :step], %{duration: _},
                       %{step_index: 0, status: :ok}}

      assert_received {:telemetry, [:phoenix_ai, :pipeline, :step], %{duration: _},
                       %{step_index: 1, status: :ok}}

      :telemetry.detach("test-pipeline-#{inspect(ref)}")
    end
  end

  describe "team complete telemetry" do
    test "emits [:phoenix_ai, :team, :complete] after merge" do
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test-team-#{inspect(ref)}",
        [:phoenix_ai, :team, :complete],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      specs = [
        fn -> {:ok, "a"} end,
        fn -> {:ok, "b"} end,
        fn -> {:error, :fail} end
      ]

      merge = fn results -> results end

      PhoenixAI.Team.run(specs, merge)

      assert_received {:telemetry, [:phoenix_ai, :team, :complete], %{duration: _},
                       %{agent_count: 3, success_count: 2, error_count: 1}}

      :telemetry.detach("test-team-#{inspect(ref)}")
    end
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_ai/telemetry_test.exs`
Expected: 2 new tests FAIL — no events emitted

- [ ] **Step 3: Add telemetry to Pipeline.run/3**

In `lib/phoenix_ai/pipeline.ex`, modify `run/3` to emit step events:

```elixir
  def run(steps, input, _opts) do
    steps
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, input}, fn {step, index}, {:ok, value} ->
      start_time = System.monotonic_time()
      result = normalize_return(step.(value))
      duration = System.monotonic_time() - start_time
      status = if match?({:ok, _}, result), do: :ok, else: :error

      :telemetry.execute(
        [:phoenix_ai, :pipeline, :step],
        %{duration: duration},
        %{step_index: index, status: status}
      )

      case result do
        {:ok, _} = ok -> {:cont, ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end
```

- [ ] **Step 4: Add telemetry to Team.run/3**

In `lib/phoenix_ai/team.ex`, add telemetry around the execution:

```elixir
  def run(specs, merge_fn, opts \\ []) do
    max_concurrency = Keyword.get(opts, :max_concurrency, @default_max_concurrency)
    timeout = Keyword.get(opts, :timeout, :infinity)
    ordered = Keyword.get(opts, :ordered, true)

    start_time = System.monotonic_time()

    results =
      specs
      |> Task.async_stream(fn spec -> safe_execute(spec) end,
        max_concurrency: max_concurrency,
        timeout: timeout,
        on_timeout: :kill_task,
        ordered: ordered
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, reason} -> {:error, {:task_failed, reason}}
      end)

    duration = System.monotonic_time() - start_time
    success_count = Enum.count(results, &match?({:ok, _}, &1))
    error_count = length(results) - success_count

    :telemetry.execute(
      [:phoenix_ai, :team, :complete],
      %{duration: duration},
      %{agent_count: length(specs), success_count: success_count, error_count: error_count}
    )

    {:ok, merge_fn.(results)}
  end
```

- [ ] **Step 5: Run all telemetry tests**

Run: `mix test test/phoenix_ai/telemetry_test.exs`
Expected: 6 tests, 0 failures

- [ ] **Step 6: Run full suite**

Run: `mix test`
Expected: All existing tests still pass

- [ ] **Step 7: Commit**

```bash
git add lib/phoenix_ai/pipeline.ex lib/phoenix_ai/team.ex test/phoenix_ai/telemetry_test.exs
git commit -m "feat(10): add telemetry events for pipeline steps and team completion"
```

---

## Task 8: NimbleOptions — AI.chat/2 & AI.stream/2

**Files:**
- Modify: `lib/ai.ex`
- Create: `test/phoenix_ai/nimble_options_test.exs`

- [ ] **Step 1: Write failing tests — chat validation**

```elixir
# test/phoenix_ai/nimble_options_test.exs
defmodule PhoenixAI.NimbleOptionsTest do
  use ExUnit.Case, async: true
  use PhoenixAI.Test

  alias PhoenixAI.{Message, Response}

  describe "AI.chat/2 option validation" do
    test "valid opts pass through" do
      set_responses([{:ok, %Response{content: "ok"}}])

      assert {:ok, _} =
               AI.chat([%Message{role: :user, content: "hi"}],
                 provider: :test,
                 api_key: "test",
                 model: "gpt-4o"
               )
    end

    test "invalid temperature type returns validation error" do
      assert {:error, %NimbleOptions.ValidationError{}} =
               AI.chat([%Message{role: :user, content: "hi"}],
                 provider: :test,
                 api_key: "test",
                 temperature: "hot"
               )
    end

    test "invalid max_tokens type returns validation error" do
      assert {:error, %NimbleOptions.ValidationError{}} =
               AI.chat([%Message{role: :user, content: "hi"}],
                 provider: :test,
                 api_key: "test",
                 max_tokens: -5
               )
    end
  end

  describe "AI.stream/2 option validation" do
    test "valid stream opts pass through" do
      set_responses([{:ok, %Response{content: "ok"}}])

      assert {:ok, _} =
               AI.stream([%Message{role: :user, content: "hi"}],
                 provider: :test,
                 api_key: "test",
                 on_chunk: fn _chunk -> :ok end
               )
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/phoenix_ai/nimble_options_test.exs`
Expected: FAIL — no validation happening, invalid opts pass through

- [ ] **Step 3: Add NimbleOptions schema and validation to AI module**

In `lib/ai.ex`, add schemas and validation. Add after `alias PhoenixAI.{Config, Schema}`:

```elixir
  @chat_schema NimbleOptions.new!([
    provider: [type: :atom, doc: "Provider identifier (:openai, :anthropic, :openrouter, :test)"],
    model: [type: :string, doc: "Model identifier"],
    api_key: [type: :string, doc: "API key — overrides config/env resolution"],
    temperature: [type: :float, doc: "Sampling temperature (0.0-2.0)"],
    max_tokens: [type: :pos_integer, doc: "Maximum tokens in response"],
    tools: [type: {:list, :atom}, default: [], doc: "Tool modules implementing PhoenixAI.Tool"],
    schema: [type: :any, doc: "JSON schema map for structured output validation"],
    provider_options: [type: {:map, :atom, :any}, default: %{}, doc: "Provider-specific passthrough"]
  ])

  @stream_schema NimbleOptions.new!(
    NimbleOptions.schema(@chat_schema) ++
      [
        on_chunk: [type: {:fun, 1}, doc: "Callback receiving %StreamChunk{} structs"],
        to: [type: :pid, doc: "PID to receive {:phoenix_ai, {:chunk, chunk}} messages"]
      ]
  )
```

Wrap `chat/2`:
```elixir
  def chat(messages, opts \\ []) do
    case NimbleOptions.validate(opts, @chat_schema) do
      {:ok, validated_opts} -> do_chat(messages, validated_opts)
      {:error, _} = error -> error
    end
  end

  defp do_chat(messages, opts) do
    provider_atom = opts[:provider] || default_provider()
    meta = %{provider: provider_atom, model: opts[:model]}

    :telemetry.span([:phoenix_ai, :chat], meta, fn ->
      case resolve_provider(provider_atom) do
        {:ok, provider_mod} ->
          merged_opts = Config.resolve(provider_atom, Keyword.delete(opts, :provider))
          result = dispatch(provider_mod, messages, merged_opts, provider_atom)
          stop_meta = Map.merge(meta, telemetry_stop_meta(result))
          {result, stop_meta}

        {:error, _} = error ->
          {error, Map.put(meta, :status, :error)}
      end
    end)
  end
```

Wrap `stream/2` similarly:
```elixir
  def stream(messages, opts \\ []) do
    case NimbleOptions.validate(opts, @stream_schema) do
      {:ok, validated_opts} -> do_stream(messages, validated_opts)
      {:error, _} = error -> error
    end
  end

  defp do_stream(messages, opts) do
    provider_atom = opts[:provider] || default_provider()
    meta = %{provider: provider_atom, model: opts[:model]}

    :telemetry.span([:phoenix_ai, :stream], meta, fn ->
      case resolve_provider(provider_atom) do
        {:ok, provider_mod} ->
          merged_opts = Config.resolve(provider_atom, Keyword.delete(opts, :provider))
          result = dispatch_stream(provider_mod, messages, merged_opts, provider_atom)
          stop_meta = Map.merge(meta, telemetry_stop_meta(result))
          {result, stop_meta}

        {:error, _} = error ->
          {error, Map.put(meta, :status, :error)}
      end
    end)
  end
```

- [ ] **Step 4: Run tests**

Run: `mix test test/phoenix_ai/nimble_options_test.exs`
Expected: 4 tests, 0 failures

- [ ] **Step 5: Run full suite to check nothing broke**

Run: `mix test`
Expected: All pass

- [ ] **Step 6: Commit**

```bash
git add lib/ai.ex test/phoenix_ai/nimble_options_test.exs
git commit -m "feat(10): add NimbleOptions validation to AI.chat/2 and AI.stream/2"
```

---

## Task 9: NimbleOptions — Agent.start_link/1

**Files:**
- Modify: `lib/phoenix_ai/agent.ex`
- Modify: `test/phoenix_ai/nimble_options_test.exs`

- [ ] **Step 1: Write failing test**

Append to `test/phoenix_ai/nimble_options_test.exs`:

```elixir
  describe "Agent.start_link/1 option validation" do
    test "missing required :provider returns validation error" do
      assert {:error, %NimbleOptions.ValidationError{}} =
               PhoenixAI.Agent.start_link(model: "gpt-4o")
    end

    test "invalid :manage_history type returns validation error" do
      assert {:error, %NimbleOptions.ValidationError{}} =
               PhoenixAI.Agent.start_link(provider: :test, manage_history: "yes")
    end

    test "valid opts start the agent" do
      set_responses([])

      assert {:ok, pid} =
               PhoenixAI.Agent.start_link(provider: :test, api_key: "test")

      Process.exit(pid, :normal)
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/phoenix_ai/nimble_options_test.exs --only describe:"Agent.start_link"`
Expected: FAIL — no validation happening

- [ ] **Step 3: Add NimbleOptions to Agent.start_link/1**

In `lib/phoenix_ai/agent.ex`, add schema after the `defstruct`:

```elixir
  @start_schema NimbleOptions.new!([
    provider: [type: :atom, required: true, doc: "Provider identifier"],
    model: [type: :string, doc: "Model identifier"],
    system: [type: :string, doc: "System prompt"],
    tools: [type: {:list, :atom}, default: [], doc: "Tool modules"],
    manage_history: [type: :boolean, default: true, doc: "Auto-accumulate messages between prompts"],
    schema: [type: :any, doc: "JSON schema for structured output"],
    name: [type: :any, doc: "GenServer name registration"],
    api_key: [type: :string, doc: "API key"]
  ])
```

Modify `start_link/1`:
```elixir
  def start_link(opts) do
    case NimbleOptions.validate(opts, @start_schema) do
      {:ok, validated_opts} ->
        {name, init_opts} = Keyword.pop(validated_opts, :name)
        gen_opts = if name, do: [name: name], else: []
        GenServer.start_link(__MODULE__, init_opts, gen_opts)

      {:error, _} = error ->
        error
    end
  end
```

- [ ] **Step 4: Run tests**

Run: `mix test test/phoenix_ai/nimble_options_test.exs`
Expected: 7 tests, 0 failures

- [ ] **Step 5: Run full suite**

Run: `mix test`
Expected: All pass

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_ai/agent.ex test/phoenix_ai/nimble_options_test.exs
git commit -m "feat(10): add NimbleOptions validation to Agent.start_link/1"
```

---

## Task 10: NimbleOptions — Team.run/3

**Files:**
- Modify: `lib/phoenix_ai/team.ex`
- Modify: `test/phoenix_ai/nimble_options_test.exs`

- [ ] **Step 1: Write failing test**

Append to `test/phoenix_ai/nimble_options_test.exs`:

```elixir
  describe "Team.run/3 option validation" do
    test "invalid :max_concurrency type returns validation error" do
      assert {:error, %NimbleOptions.ValidationError{}} =
               PhoenixAI.Team.run([fn -> :ok end], fn r -> r end, max_concurrency: "many")
    end

    test "valid opts pass through" do
      assert {:ok, _} =
               PhoenixAI.Team.run([fn -> {:ok, "a"} end], fn r -> r end, max_concurrency: 2)
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/phoenix_ai/nimble_options_test.exs --only describe:"Team.run"`
Expected: FAIL — no validation

- [ ] **Step 3: Add NimbleOptions to Team.run/3**

In `lib/phoenix_ai/team.ex`, add schema before `run/3`:

```elixir
  @run_schema NimbleOptions.new!([
    max_concurrency: [type: :pos_integer, default: 5, doc: "Max parallel tasks"],
    timeout: [type: {:in, [:infinity | 1..(:infinity)]}, default: :infinity, doc: "Per-task timeout in ms"],
    ordered: [type: :boolean, default: true, doc: "Preserve input order in results"]
  ])
```

Note: The `timeout` NimbleOptions type needs care. Since NimbleOptions doesn't directly support `pos_integer | :infinity`, use a custom validation:

```elixir
  @run_schema NimbleOptions.new!([
    max_concurrency: [type: :pos_integer, default: 5, doc: "Max parallel tasks"],
    timeout: [
      type: {:custom, __MODULE__, :validate_timeout, []},
      default: :infinity,
      doc: "Per-task timeout in ms (:infinity or positive integer)"
    ],
    ordered: [type: :boolean, default: true, doc: "Preserve input order in results"]
  ])

  @doc false
  def validate_timeout(:infinity), do: {:ok, :infinity}
  def validate_timeout(val) when is_integer(val) and val > 0, do: {:ok, val}
  def validate_timeout(val), do: {:error, "expected :infinity or positive integer, got: #{inspect(val)}"}
```

Wrap `run/3`:
```elixir
  def run(specs, merge_fn, opts \\ []) do
    case NimbleOptions.validate(opts, @run_schema) do
      {:ok, validated_opts} -> do_run(specs, merge_fn, validated_opts)
      {:error, _} = error -> error
    end
  end

  defp do_run(specs, merge_fn, opts) do
    # ... existing implementation moved here
  end
```

- [ ] **Step 4: Run tests**

Run: `mix test test/phoenix_ai/nimble_options_test.exs`
Expected: 9 tests, 0 failures

- [ ] **Step 5: Run full suite**

Run: `mix test`
Expected: All pass

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_ai/team.ex test/phoenix_ai/nimble_options_test.exs
git commit -m "feat(10): add NimbleOptions validation to Team.run/3"
```

---

## Task 11: ExDoc — Guides

**Files:**
- Create: `guides/getting-started.md`
- Create: `guides/provider-setup.md`
- Create: `guides/agents-and-tools.md`
- Create: `guides/pipelines-and-teams.md`
- Modify: `mix.exs`

- [ ] **Step 1: Create guides directory**

```bash
mkdir -p guides/cookbook
```

- [ ] **Step 2: Write getting-started.md**

```markdown
# Getting Started

PhoenixAI is an Elixir library for integrating AI providers (OpenAI, Anthropic, OpenRouter) with a unified API, tool calling, agents, pipelines, and parallel team execution.

## Installation

Add `phoenix_ai` to your dependencies in `mix.exs`:

    {:phoenix_ai, "~> 0.1"}

Then run:

    mix deps.get

## Configuration

Set your API keys via environment variables:

    export OPENAI_API_KEY=sk-...
    export ANTHROPIC_API_KEY=sk-ant-...

Or configure in `config/config.exs`:

    config :phoenix_ai, :openai,
      api_key: "sk-...",
      model: "gpt-4o"

    config :phoenix_ai, :anthropic,
      api_key: "sk-ant-...",
      model: "claude-sonnet-4-5"

## Your First Call

    alias PhoenixAI.{Message, Response}

    messages = [%Message{role: :user, content: "What is Elixir?"}]

    {:ok, %Response{content: content}} =
      AI.chat(messages, provider: :openai)

    IO.puts(content)
    # => "Elixir is a dynamic, functional language designed for building scalable..."

## Understanding the Response

`AI.chat/2` returns `{:ok, %Response{}}` or `{:error, reason}`:

    %Response{
      content: "The response text",
      usage: %{"prompt_tokens" => 10, "completion_tokens" => 25, "total_tokens" => 35},
      finish_reason: "stop",
      tool_calls: [],
      model: "gpt-4o"
    }

## Next Steps

- [Provider Setup](provider-setup.md) — configure each provider
- [Agents & Tools](agents-and-tools.md) — stateful agents with tool calling
- [Pipelines & Teams](pipelines-and-teams.md) — orchestration patterns
```

- [ ] **Step 3: Write provider-setup.md**

```markdown
# Provider Setup

PhoenixAI supports OpenAI, Anthropic, and OpenRouter out of the box, plus a TestProvider for offline testing.

## Configuration Cascade

Options resolve in this order (highest priority first):

1. **Call-site options** — passed directly to `AI.chat/2`
2. **Application config** — `config :phoenix_ai, :openai, ...`
3. **Environment variables** — `OPENAI_API_KEY`, etc.
4. **Provider defaults** — built-in model defaults

## OpenAI

    AI.chat(messages, provider: :openai, model: "gpt-4o")

Environment variable: `OPENAI_API_KEY`

## Anthropic

    AI.chat(messages, provider: :anthropic, model: "claude-sonnet-4-5")

Environment variable: `ANTHROPIC_API_KEY`

Anthropic requires `max_tokens` — it defaults to 4096 for streaming.

## OpenRouter

    AI.chat(messages, provider: :openrouter, model: "meta-llama/llama-3-70b")

Environment variable: `OPENROUTER_API_KEY`

OpenRouter is OpenAI-compatible, so it accepts the same options.

## Provider-Specific Options

Use `provider_options:` for options not part of the unified API:

    AI.chat(messages,
      provider: :openai,
      provider_options: %{
        frequency_penalty: 0.5,
        presence_penalty: 0.3
      }
    )

These are passed through untouched to the provider's HTTP request.

## TestProvider

For testing without network calls:

    # In your test
    use PhoenixAI.Test

    test "my feature" do
      set_responses([{:ok, %Response{content: "scripted"}}])
      assert {:ok, %Response{content: "scripted"}} =
        AI.chat(messages, provider: :test, api_key: "test")
    end

See `PhoenixAI.Test` module docs for full API.
```

- [ ] **Step 4: Write agents-and-tools.md**

```markdown
# Agents & Tools

## Tools

Tools are plain Elixir modules implementing the `PhoenixAI.Tool` behaviour:

    defmodule MyApp.Weather do
      @behaviour PhoenixAI.Tool

      @impl true
      def name, do: "get_weather"

      @impl true
      def description, do: "Get current weather for a city"

      @impl true
      def parameters_schema do
        %{
          type: :object,
          properties: %{
            city: %{type: :string, description: "City name"}
          },
          required: [:city]
        }
      end

      @impl true
      def execute(%{"city" => city}, _opts) do
        # Call your weather API here
        {:ok, "Sunny, 22°C in #{city}"}
      end
    end

Pass tools to `AI.chat/2` — the library automatically loops (call → detect tool calls → execute → re-call) until the model stops:

    AI.chat(messages, provider: :openai, tools: [MyApp.Weather])

## Agent GenServer

For stateful conversations that persist across multiple prompts:

    {:ok, agent} = PhoenixAI.Agent.start_link(
      provider: :openai,
      model: "gpt-4o",
      system: "You are a helpful assistant.",
      tools: [MyApp.Weather]
    )

    {:ok, resp1} = PhoenixAI.Agent.prompt(agent, "What's the weather in Lisbon?")
    # Agent remembers context...
    {:ok, resp2} = PhoenixAI.Agent.prompt(agent, "And in Porto?")

### History Management

By default, the agent accumulates messages (`manage_history: true`). For external history management:

    {:ok, agent} = PhoenixAI.Agent.start_link(
      provider: :openai,
      manage_history: false
    )

    # Pass messages explicitly each time
    PhoenixAI.Agent.prompt(agent, "Hi", messages: my_messages)

### Supervision

Start agents under a DynamicSupervisor:

    DynamicSupervisor.start_child(MyApp.AgentSupervisor, {PhoenixAI.Agent, opts})
```

- [ ] **Step 5: Write pipelines-and-teams.md**

```markdown
# Pipelines & Teams

## Pipeline — Sequential Execution

Steps execute in order. Each step receives the previous step's result. Halts on first error.

### Ad-hoc

    alias PhoenixAI.Pipeline

    Pipeline.run([
      fn query -> AI.chat([%Message{role: :user, content: query}], provider: :openai) end,
      fn %Response{content: text} -> {:ok, String.upcase(text)} end
    ], "Summarize Elixir")

### DSL

    defmodule MyPipeline do
      use PhoenixAI.Pipeline

      step :search do
        fn query ->
          AI.chat([%Message{role: :user, content: "Search: #{query}"}], provider: :openai)
        end
      end

      step :summarize do
        fn %Response{content: text} ->
          AI.chat([%Message{role: :user, content: "Summarize: #{text}"}], provider: :openai)
        end
      end
    end

    MyPipeline.run("Elixir concurrency")

## Team — Parallel Execution

Multiple agents run concurrently. Results are merged by a caller-supplied function.

### Ad-hoc

    alias PhoenixAI.Team

    Team.run(
      [
        fn -> AI.chat([%Message{role: :user, content: "Research topic A"}], provider: :openai) end,
        fn -> AI.chat([%Message{role: :user, content: "Research topic B"}], provider: :anthropic) end
      ],
      fn results ->
        results
        |> Enum.filter(&match?({:ok, _}, &1))
        |> Enum.map(fn {:ok, r} -> r.content end)
        |> Enum.join("\n\n")
      end,
      max_concurrency: 5
    )

### DSL

    defmodule MyTeam do
      use PhoenixAI.Team

      agent :researcher do
        fn -> AI.chat([%Message{role: :user, content: "Research"}], provider: :openai) end
      end

      agent :analyst do
        fn -> AI.chat([%Message{role: :user, content: "Analyze"}], provider: :anthropic) end
      end

      merge do
        fn results -> Enum.map(results, fn {:ok, r} -> r.content end) end
      end
    end

    MyTeam.run()

## Composition

Pipeline steps can invoke Teams, and Team agents can invoke Pipelines:

    Pipeline.run([
      fn query -> {:ok, query} end,
      fn query ->
        Team.run(
          [
            fn -> AI.chat([msg("Search A: #{query}")], provider: :openai) end,
            fn -> AI.chat([msg("Search B: #{query}")], provider: :anthropic) end
          ],
          fn results -> {:ok, merge_results(results)} end
        )
      end,
      fn merged -> AI.chat([msg("Summarize: #{merged}")], provider: :openai) end
    ], "Elixir vs Erlang")
```

- [ ] **Step 6: Update mix.exs docs config**

In `mix.exs`, replace the `docs/0` function:

```elixir
  defp docs do
    [
      main: "getting-started",
      extras: [
        "guides/getting-started.md",
        "guides/provider-setup.md",
        "guides/agents-and-tools.md",
        "guides/pipelines-and-teams.md",
        "guides/cookbook/rag-pipeline.md",
        "guides/cookbook/multi-agent-team.md",
        "guides/cookbook/streaming-liveview.md",
        "guides/cookbook/custom-tools.md"
      ],
      groups_for_extras: [
        Guides: ~r/guides\/[^\/]+\.md$/,
        Cookbook: ~r/guides\/cookbook\/.+\.md$/
      ],
      groups_for_modules: [
        Core: [AI, PhoenixAI.Message, PhoenixAI.Response, PhoenixAI.Conversation],
        Providers: [~r/PhoenixAI\.Providers\./],
        "Tools & Agent": [PhoenixAI.Tool, PhoenixAI.Agent, PhoenixAI.ToolLoop],
        Orchestration: [PhoenixAI.Pipeline, PhoenixAI.Team],
        Streaming: [PhoenixAI.Stream, PhoenixAI.StreamChunk],
        "Schema & Config": [PhoenixAI.Schema, PhoenixAI.Config],
        Testing: [PhoenixAI.Test, PhoenixAI.Providers.TestProvider]
      ]
    ]
  end
```

- [ ] **Step 7: Verify docs compile**

Run: `mix docs`
Expected: Docs generate without warnings. Check `doc/` output.

- [ ] **Step 8: Commit**

```bash
git add guides/ mix.exs
git commit -m "docs(10): add ExDoc guides — getting started, providers, agents, pipelines"
```

---

## Task 12: ExDoc — Cookbook Recipes

**Files:**
- Create: `guides/cookbook/rag-pipeline.md`
- Create: `guides/cookbook/multi-agent-team.md`
- Create: `guides/cookbook/streaming-liveview.md`
- Create: `guides/cookbook/custom-tools.md`

- [ ] **Step 1: Write rag-pipeline.md**

```markdown
# Cookbook: RAG Pipeline

A Retrieval-Augmented Generation pattern using `PhoenixAI.Pipeline`:

    defmodule MyApp.RAGPipeline do
      use PhoenixAI.Pipeline

      step :search do
        fn query ->
          # Your search/retrieval logic here (e.g., Ecto query, vector DB)
          results = MyApp.Search.query(query)
          {:ok, %{query: query, context: results}}
        end
      end

      step :generate do
        fn %{query: query, context: context} ->
          prompt = """
          Answer the question using ONLY the provided context.

          Context: #{context}
          Question: #{query}
          """

          AI.chat([%PhoenixAI.Message{role: :user, content: prompt}], provider: :openai)
        end
      end
    end

    {:ok, %Response{content: answer}} = MyApp.RAGPipeline.run("How do I deploy?")

The pipeline halts if the search step fails, so the LLM is never called with empty context.
```

- [ ] **Step 2: Write multi-agent-team.md**

```markdown
# Cookbook: Multi-Agent Team

Run multiple AI agents in parallel and merge their outputs:

    defmodule MyApp.ResearchTeam do
      use PhoenixAI.Team

      agent :technical do
        fn ->
          AI.chat(
            [%PhoenixAI.Message{role: :user, content: "Technical analysis of Elixir GenServers"}],
            provider: :openai,
            model: "gpt-4o"
          )
        end
      end

      agent :business do
        fn ->
          AI.chat(
            [%PhoenixAI.Message{role: :user, content: "Business case for Elixir adoption"}],
            provider: :anthropic,
            model: "claude-sonnet-4-5"
          )
        end
      end

      merge do
        fn results ->
          results
          |> Enum.filter(&match?({:ok, _}, &1))
          |> Enum.map(fn {:ok, %PhoenixAI.Response{content: c}} -> c end)
          |> Enum.join("\n\n---\n\n")
        end
      end
    end

    {:ok, combined} = MyApp.ResearchTeam.run(max_concurrency: 2)

Both agents run simultaneously. The merge function combines successful results and ignores failures.
```

- [ ] **Step 3: Write streaming-liveview.md**

```markdown
# Cookbook: Streaming to LiveView

Stream AI responses to a Phoenix LiveView process in real time:

    # In your LiveView
    def handle_event("ask", %{"prompt" => prompt}, socket) do
      messages = [%PhoenixAI.Message{role: :user, content: prompt}]

      Task.start(fn ->
        AI.stream(messages,
          provider: :openai,
          to: socket.root_pid,
          api_key: System.get_env("OPENAI_API_KEY")
        )
      end)

      {:noreply, assign(socket, :response, "")}
    end

    def handle_info({:phoenix_ai, {:chunk, %PhoenixAI.StreamChunk{delta: delta}}}, socket)
        when is_binary(delta) do
      {:noreply, assign(socket, :response, socket.assigns.response <> delta)}
    end

    def handle_info({:phoenix_ai, {:chunk, %PhoenixAI.StreamChunk{finish_reason: "stop"}}}, socket) do
      {:noreply, socket}
    end

The `to: pid` option sends `{:phoenix_ai, {:chunk, %StreamChunk{}}}` messages to the target process. Each chunk contains a `delta` (text fragment) or a `finish_reason` when the stream completes.

Alternatively, use `on_chunk:` with a callback:

    AI.stream(messages,
      provider: :openai,
      on_chunk: fn chunk ->
        if chunk.delta, do: Phoenix.PubSub.broadcast(MyApp.PubSub, "chat:123", {:chunk, chunk.delta})
      end
    )
```

- [ ] **Step 4: Write custom-tools.md**

```markdown
# Cookbook: Custom Tools

Build tools that AI models can call during conversations.

## Basic Tool

    defmodule MyApp.Calculator do
      @behaviour PhoenixAI.Tool

      @impl true
      def name, do: "calculator"

      @impl true
      def description, do: "Evaluate a mathematical expression"

      @impl true
      def parameters_schema do
        %{
          type: :object,
          properties: %{
            expression: %{type: :string, description: "Math expression (e.g., '2 + 3 * 4')"}
          },
          required: [:expression]
        }
      end

      @impl true
      def execute(%{"expression" => expr}, _opts) do
        case Code.eval_string(expr) do
          {result, _} -> {:ok, to_string(result)}
        end
      rescue
        _ -> {:error, "Invalid expression: #{expr}"}
      end
    end

## Using Tools

    AI.chat(
      [%Message{role: :user, content: "What is 15 * 37 + 42?"}],
      provider: :openai,
      tools: [MyApp.Calculator]
    )

The library automatically:
1. Sends the tool schema to the provider
2. Detects tool call requests in the response
3. Executes `MyApp.Calculator.execute/2` with the arguments
4. Sends the result back to the provider
5. Returns the final response

## Tool with External API

    defmodule MyApp.GitHubSearch do
      @behaviour PhoenixAI.Tool

      @impl true
      def name, do: "search_github"

      @impl true
      def description, do: "Search GitHub repositories"

      @impl true
      def parameters_schema do
        %{
          type: :object,
          properties: %{
            query: %{type: :string, description: "Search query"},
            language: %{type: :string, description: "Programming language filter"}
          },
          required: [:query]
        }
      end

      @impl true
      def execute(%{"query" => query} = args, _opts) do
        language = Map.get(args, "language", "")
        q = if language != "", do: "#{query} language:#{language}", else: query

        case Req.get("https://api.github.com/search/repositories", params: [q: q, per_page: 5]) do
          {:ok, %{status: 200, body: %{"items" => items}}} ->
            results = Enum.map(items, & &1["full_name"]) |> Enum.join(", ")
            {:ok, results}

          {:error, reason} ->
            {:error, inspect(reason)}
        end
      end
    end

## Testing Tools

Use the TestProvider to test tool-using code offline:

    use PhoenixAI.Test

    test "agent uses weather tool" do
      set_handler(fn messages, _opts ->
        # Simulate: first call returns tool call, second returns final answer
        if length(messages) <= 2 do
          {:ok, %Response{
            content: nil,
            tool_calls: [%ToolCall{id: "tc1", name: "get_weather", arguments: %{"city" => "Lisbon"}}]
          }}
        else
          {:ok, %Response{content: "It's sunny in Lisbon!"}}
        end
      end)

      {:ok, resp} = AI.chat(
        [%Message{role: :user, content: "Weather in Lisbon?"}],
        provider: :test,
        api_key: "test",
        tools: [MyApp.Weather]
      )

      assert resp.content == "It's sunny in Lisbon!"
    end
```

- [ ] **Step 5: Verify docs compile with cookbook**

Run: `mix docs`
Expected: All guides and cookbook recipes appear in generated docs

- [ ] **Step 6: Commit**

```bash
git add guides/cookbook/
git commit -m "docs(10): add cookbook recipes — RAG, multi-agent, streaming, custom tools"
```

---

## Task 13: Hex Publish Readiness

**Files:**
- Modify: `mix.exs`

- [ ] **Step 1: Add files list to package config**

In `mix.exs`, update `package/0`:

```elixir
  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib guides mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end
```

- [ ] **Step 2: Verify hex build succeeds**

Run: `mix hex.build --unpack`
Expected: Package builds successfully, only listed files are included. No `.planning/`, `test/`, or other internal files.

If `hex.build` is not available locally, verify with:

Run: `mix hex.build`
Expected: `phoenix_ai-0.1.0.tar` created

- [ ] **Step 3: Run full test suite and credo**

Run: `mix test && mix credo`
Expected: All tests pass, no credo issues

- [ ] **Step 4: Commit**

```bash
git add mix.exs
git commit -m "chore(10): add files list for Hex publish readiness"
```

---

## Task 14: Final Verification

- [ ] **Step 1: Run full test suite**

Run: `mix test`
Expected: All tests pass

- [ ] **Step 2: Run credo**

Run: `mix credo`
Expected: No issues

- [ ] **Step 3: Generate docs**

Run: `mix docs`
Expected: No warnings, guides and cookbook appear correctly

- [ ] **Step 4: Verify DX requirements**

Check each requirement:
- **DX-01:** `AI.chat(msgs, provider: :test)` returns scripted response — verified by TestProvider tests
- **DX-02:** Telemetry events fire for chat start/stop/exception — verified by telemetry tests
- **DX-03:** Invalid opts return `{:error, %NimbleOptions.ValidationError{}}` — verified by NimbleOptions tests
- **DX-04:** `mix docs` generates complete documentation with guides and cookbook
- **DX-05:** `mix hex.build` succeeds with correct file list and `~> major.minor` deps
