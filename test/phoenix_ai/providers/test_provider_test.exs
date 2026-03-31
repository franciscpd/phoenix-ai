defmodule PhoenixAI.Providers.TestProviderTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Providers.TestProvider
  alias PhoenixAI.{Response, StreamChunk}

  setup do
    {:ok, _} = TestProvider.start_state(self())
    on_exit(fn -> TestProvider.stop_state(self()) end)
    :ok
  end

  # ---------------------------------------------------------------------------
  # Task 1: Queue Mode
  # ---------------------------------------------------------------------------

  describe "chat/2 — queue mode" do
    test "returns responses in FIFO order" do
      r1 = {:ok, %Response{content: "first"}}
      r2 = {:ok, %Response{content: "second"}}
      r3 = {:ok, %Response{content: "third"}}

      TestProvider.put_responses(self(), [r1, r2, r3])

      assert TestProvider.chat([], []) == r1
      assert TestProvider.chat([], []) == r2
      assert TestProvider.chat([], []) == r3
    end

    test "returns :no_more_responses error when queue is exhausted" do
      TestProvider.put_responses(self(), [{:ok, %Response{content: "only one"}}])

      assert {:ok, %Response{content: "only one"}} = TestProvider.chat([], [])
      assert {:error, :no_more_responses} = TestProvider.chat([], [])
    end

    test "returns :test_provider_not_configured when no state is set up" do
      result =
        Task.async(fn ->
          # This task's PID has no state registered
          TestProvider.chat([], [])
        end)
        |> Task.await()

      assert result == {:error, :test_provider_not_configured}
    end

    test "queue can be extended with multiple put_responses calls" do
      TestProvider.put_responses(self(), [{:ok, %Response{content: "a"}}])
      TestProvider.put_responses(self(), [{:ok, %Response{content: "b"}}])

      assert {:ok, %Response{content: "a"}} = TestProvider.chat([], [])
      assert {:ok, %Response{content: "b"}} = TestProvider.chat([], [])
    end
  end
end
