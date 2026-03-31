defmodule PhoenixAI.NimbleOptionsTest do
  use ExUnit.Case, async: false
  use PhoenixAI.Test

  import Mox

  setup :verify_on_exit!

  alias PhoenixAI.{Agent, Message, Response, Team}

  # -----------------------------------------------------------------------
  # Task 8: AI.chat/2 & AI.stream/2 NimbleOptions validation
  # -----------------------------------------------------------------------

  describe "AI.chat/2 NimbleOptions validation" do
    test "valid opts pass through and work" do
      set_responses([{:ok, %Response{content: "Hello!", tool_calls: [], finish_reason: "stop"}}])

      assert {:ok, %Response{content: "Hello!"}} =
               AI.chat(
                 [%Message{role: :user, content: "Hi"}],
                 provider: :test,
                 api_key: "test-key",
                 model: "test-model"
               )
    end

    test "invalid temperature type (string) returns NimbleOptions.ValidationError" do
      result =
        AI.chat(
          [%Message{role: :user, content: "Hi"}],
          provider: :test,
          api_key: "test-key",
          temperature: "hot"
        )

      assert {:error, %NimbleOptions.ValidationError{}} = result
    end

    test "invalid max_tokens (negative integer) returns validation error" do
      result =
        AI.chat(
          [%Message{role: :user, content: "Hi"}],
          provider: :test,
          api_key: "test-key",
          max_tokens: -1
        )

      assert {:error, %NimbleOptions.ValidationError{}} = result
    end

    test "unknown option returns validation error" do
      result =
        AI.chat(
          [%Message{role: :user, content: "Hi"}],
          provider: :test,
          api_key: "test-key",
          totally_unknown_opt: true
        )

      assert {:error, %NimbleOptions.ValidationError{}} = result
    end
  end

  describe "AI.stream/2 NimbleOptions validation" do
    test "valid stream opts with on_chunk callback pass validation (no ValidationError)" do
      # Valid opts pass NimbleOptions validation — the result may be a provider error
      # but must NOT be a NimbleOptions.ValidationError.
      result =
        AI.stream(
          [%Message{role: :user, content: "Hi"}],
          provider: :openai,
          on_chunk: fn _chunk -> :ok end
        )

      refute match?({:error, %NimbleOptions.ValidationError{}}, result)
    end

    test "valid stream opts with :to pid pass validation (no ValidationError)" do
      result =
        AI.stream(
          [%Message{role: :user, content: "Hi"}],
          provider: :openai,
          to: self()
        )

      refute match?({:error, %NimbleOptions.ValidationError{}}, result)
    end

    test "invalid temperature type in stream returns validation error" do
      result =
        AI.stream(
          [%Message{role: :user, content: "Hi"}],
          provider: :test,
          api_key: "test-key",
          temperature: "warm"
        )

      assert {:error, %NimbleOptions.ValidationError{}} = result
    end

    test "invalid max_tokens (zero) returns validation error" do
      result =
        AI.stream(
          [%Message{role: :user, content: "Hi"}],
          provider: :test,
          api_key: "test-key",
          max_tokens: 0
        )

      assert {:error, %NimbleOptions.ValidationError{}} = result
    end
  end

  # -----------------------------------------------------------------------
  # Task 9: Agent.start_link/1 NimbleOptions validation
  # -----------------------------------------------------------------------

  describe "Agent.start_link/1 NimbleOptions validation" do
    test "missing required :provider returns validation error" do
      result = Agent.start_link(api_key: "test-key", model: "test-model")
      assert {:error, %NimbleOptions.ValidationError{} = err} = result
      assert err.message =~ "provider"
    end

    test "invalid :manage_history type returns validation error" do
      result =
        Agent.start_link(
          provider: :test,
          api_key: "test-key",
          manage_history: "yes"
        )

      assert {:error, %NimbleOptions.ValidationError{}} = result
    end

    test "valid opts start the agent" do
      assert {:ok, pid} =
               Agent.start_link(
                 provider: :test,
                 api_key: "test-key",
                 model: "test-model"
               )

      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "valid opts with all fields start the agent" do
      assert {:ok, pid} =
               Agent.start_link(
                 provider: :test,
                 api_key: "test-key",
                 model: "test-model",
                 system: "You are helpful.",
                 tools: [],
                 manage_history: true
               )

      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end

  # -----------------------------------------------------------------------
  # Task 10: Team.run/3 NimbleOptions validation
  # -----------------------------------------------------------------------

  describe "Team.run/3 NimbleOptions validation" do
    test "invalid max_concurrency type (string) returns validation error" do
      specs = [fn -> {:ok, "result"} end]
      merge_fn = fn results -> results end

      result = Team.run(specs, merge_fn, max_concurrency: "five")
      assert {:error, %NimbleOptions.ValidationError{}} = result
    end

    test "invalid max_concurrency (zero) returns validation error" do
      specs = [fn -> {:ok, "result"} end]
      merge_fn = fn results -> results end

      result = Team.run(specs, merge_fn, max_concurrency: 0)
      assert {:error, %NimbleOptions.ValidationError{}} = result
    end

    test "invalid timeout value returns validation error" do
      specs = [fn -> {:ok, "result"} end]
      merge_fn = fn results -> results end

      result = Team.run(specs, merge_fn, timeout: -100)
      assert {:error, %NimbleOptions.ValidationError{}} = result
    end

    test "invalid timeout type returns validation error" do
      specs = [fn -> {:ok, "result"} end]
      merge_fn = fn results -> results end

      result = Team.run(specs, merge_fn, timeout: "forever")
      assert {:error, %NimbleOptions.ValidationError{}} = result
    end

    test "valid opts pass through and run works" do
      specs = [
        fn -> {:ok, "a"} end,
        fn -> {:ok, "b"} end
      ]

      merge_fn = fn results -> Enum.map(results, fn {:ok, v} -> v end) end

      assert {:ok, ["a", "b"]} = Team.run(specs, merge_fn, max_concurrency: 2, ordered: true)
    end

    test "valid :infinity timeout passes through" do
      specs = [fn -> {:ok, "done"} end]
      merge_fn = fn results -> results end

      assert {:ok, [{:ok, "done"}]} = Team.run(specs, merge_fn, timeout: :infinity)
    end

    test "valid positive integer timeout passes through" do
      specs = [fn -> {:ok, "done"} end]
      merge_fn = fn results -> results end

      assert {:ok, [{:ok, "done"}]} = Team.run(specs, merge_fn, timeout: 5000)
    end
  end
end
