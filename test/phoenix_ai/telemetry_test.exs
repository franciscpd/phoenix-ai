defmodule PhoenixAI.TelemetryTest do
  use ExUnit.Case, async: false
  use PhoenixAI.Test

  alias PhoenixAI.{Message, Pipeline, Response, Team, ToolCall, ToolLoop}

  # Helper to attach a telemetry handler and collect events, removing it on_exit.
  defp attach_collector(test_pid, event) do
    handler_id = "test-handler-#{inspect(event)}-#{:erlang.unique_integer()}"

    :telemetry.attach(
      handler_id,
      event,
      fn _event, measurements, metadata, _config ->
        send(test_pid, {:telemetry_event, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    handler_id
  end

  # ------------------------------------------------------------------ #
  # Task 5: AI.chat/2 and AI.stream/2 spans
  # ------------------------------------------------------------------ #

  describe "AI.chat/2 telemetry" do
    test "emits :start and :stop events with correct metadata on success" do
      attach_collector(self(), [:phoenix_ai, :chat, :start])
      attach_collector(self(), [:phoenix_ai, :chat, :stop])

      set_responses([{:ok, %Response{content: "hello", usage: %{total_tokens: 10}}}])

      AI.chat([%Message{role: :user, content: "hi"}],
        provider: :test,
        model: "test-model",
        api_key: "test"
      )

      assert_received {:telemetry_event, [:phoenix_ai, :chat, :start], _measurements,
                       %{provider: :test, model: "test-model"}}

      assert_received {:telemetry_event, [:phoenix_ai, :chat, :stop], _measurements,
                       %{provider: :test, model: "test-model", status: :ok, usage: _}}
    end

    test "emits :stop event with status :error on provider failure" do
      attach_collector(self(), [:phoenix_ai, :chat, :stop])

      set_responses([{:error, :some_error}])

      AI.chat([%Message{role: :user, content: "hi"}],
        provider: :test,
        api_key: "test"
      )

      assert_received {:telemetry_event, [:phoenix_ai, :chat, :stop], _measurements,
                       %{status: :error}}
    end

    test "emits :exception event when provider raises" do
      attach_collector(self(), [:phoenix_ai, :chat, :exception])

      set_handler(fn _messages, _opts -> raise "boom" end)

      assert_raise RuntimeError, "boom", fn ->
        AI.chat([%Message{role: :user, content: "hi"}],
          provider: :test,
          api_key: "test"
        )
      end

      assert_received {:telemetry_event, [:phoenix_ai, :chat, :exception], _measurements, _meta}
    end
  end

  describe "AI.stream/2 telemetry" do
    test "emits :start event with correct metadata" do
      attach_collector(self(), [:phoenix_ai, :stream, :start])

      # Trigger stream — missing api_key will fail early but :start is emitted first.
      AI.stream([%Message{role: :user, content: "hi"}],
        provider: :openai,
        model: "stream-model"
      )

      assert_received {:telemetry_event, [:phoenix_ai, :stream, :start], _measurements,
                       %{provider: :openai, model: "stream-model"}}
    end

    test "emits :stop event with status :error on missing api_key" do
      attach_collector(self(), [:phoenix_ai, :stream, :stop])

      AI.stream([%Message{role: :user, content: "hi"}],
        provider: :openai,
        model: "stream-model"
      )

      assert_received {:telemetry_event, [:phoenix_ai, :stream, :stop], _measurements,
                       %{provider: :openai, model: "stream-model", status: :error}}
    end
  end

  # ------------------------------------------------------------------ #
  # Task 6: ToolLoop tool call events
  # ------------------------------------------------------------------ #

  describe "ToolLoop tool call telemetry" do
    test "emits :start and :stop events with tool name on successful tool call" do
      attach_collector(self(), [:phoenix_ai, :tool_call, :start])
      attach_collector(self(), [:phoenix_ai, :tool_call, :stop])

      tool_calls = [
        %ToolCall{id: "tc1", name: "get_weather", arguments: %{"city" => "London"}}
      ]

      ToolLoop.execute_and_build_results(
        tool_calls,
        [PhoenixAI.TestTools.WeatherTool],
        []
      )

      assert_received {:telemetry_event, [:phoenix_ai, :tool_call, :start], %{},
                       %{tool: "get_weather"}}

      assert_received {:telemetry_event, [:phoenix_ai, :tool_call, :stop], %{duration: duration},
                       %{tool: "get_weather", status: :ok}}

      assert is_integer(duration)
    end

    test "emits :stop event with status :error when tool is unknown" do
      attach_collector(self(), [:phoenix_ai, :tool_call, :stop])

      tool_calls = [
        %ToolCall{id: "tc2", name: "unknown_tool", arguments: %{}}
      ]

      ToolLoop.execute_and_build_results(tool_calls, [], [])

      assert_received {:telemetry_event, [:phoenix_ai, :tool_call, :stop], _measurements,
                       %{tool: "unknown_tool", status: :error}}
    end
  end

  # ------------------------------------------------------------------ #
  # Task 7: Pipeline step events
  # ------------------------------------------------------------------ #

  describe "Pipeline step telemetry" do
    test "emits one :step event per step with correct step_index and status :ok" do
      attach_collector(self(), [:phoenix_ai, :pipeline, :step])

      steps = [
        fn input -> {:ok, input <> "_1"} end,
        fn input -> {:ok, input <> "_2"} end
      ]

      assert {:ok, "start_1_2"} = Pipeline.run(steps, "start")

      assert_received {:telemetry_event, [:phoenix_ai, :pipeline, :step], %{duration: _},
                       %{step_index: 0, status: :ok}}

      assert_received {:telemetry_event, [:phoenix_ai, :pipeline, :step], %{duration: _},
                       %{step_index: 1, status: :ok}}
    end

    test "emits :step event with status :error on failing step" do
      attach_collector(self(), [:phoenix_ai, :pipeline, :step])

      steps = [
        fn input -> {:ok, input} end,
        fn _input -> {:error, :failed} end
      ]

      assert {:error, :failed} = Pipeline.run(steps, "start")

      assert_received {:telemetry_event, [:phoenix_ai, :pipeline, :step], _,
                       %{step_index: 0, status: :ok}}

      assert_received {:telemetry_event, [:phoenix_ai, :pipeline, :step], _,
                       %{step_index: 1, status: :error}}
    end
  end

  # ------------------------------------------------------------------ #
  # Task 7: Team complete event
  # ------------------------------------------------------------------ #

  describe "Team complete telemetry" do
    test "emits :complete event with correct counts after team run" do
      attach_collector(self(), [:phoenix_ai, :team, :complete])

      specs = [
        fn -> {:ok, "result_a"} end,
        fn -> {:ok, "result_b"} end,
        fn -> {:error, :boom} end
      ]

      merge_fn = fn results -> results end

      assert {:ok, _results} = Team.run(specs, merge_fn)

      assert_received {:telemetry_event, [:phoenix_ai, :team, :complete], %{duration: duration},
                       %{agent_count: 3, success_count: 2, error_count: 1}}

      assert is_integer(duration)
    end

    test "emits :complete with agent_count 0 for empty specs" do
      attach_collector(self(), [:phoenix_ai, :team, :complete])

      assert {:ok, []} = Team.run([], fn results -> results end)

      assert_received {:telemetry_event, [:phoenix_ai, :team, :complete], _,
                       %{agent_count: 0, success_count: 0, error_count: 0}}
    end
  end
end
