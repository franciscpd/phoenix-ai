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

  # ---------------------------------------------------------------------------
  # Task 2: Handler Mode & Call Log
  # ---------------------------------------------------------------------------

  describe "chat/2 — handler mode" do
    test "handler is called with messages and opts" do
      messages = [%{role: "user", content: "hello"}]
      opts = [temperature: 0.5]

      TestProvider.put_handler(self(), fn msgs, o ->
        assert msgs == messages
        assert o == opts
        {:ok, %Response{content: "from handler"}}
      end)

      assert {:ok, %Response{content: "from handler"}} = TestProvider.chat(messages, opts)
    end

    test "handler return value is passed through directly" do
      TestProvider.put_handler(self(), fn _msgs, _opts ->
        {:error, :something_went_wrong}
      end)

      assert {:error, :something_went_wrong} = TestProvider.chat([], [])
    end

    test "handler takes precedence over queued responses" do
      TestProvider.put_responses(self(), [{:ok, %Response{content: "from queue"}}])

      TestProvider.put_handler(self(), fn _msgs, _opts ->
        {:ok, %Response{content: "from handler"}}
      end)

      assert {:ok, %Response{content: "from handler"}} = TestProvider.chat([], [])
    end
  end

  describe "call log" do
    test "records messages and opts for each chat/2 call in queue mode" do
      messages1 = [%{role: "user", content: "first message"}]
      messages2 = [%{role: "user", content: "second message"}]
      opts1 = [temperature: 0.1]
      opts2 = [temperature: 0.9]

      TestProvider.put_responses(self(), [
        {:ok, %Response{content: "r1"}},
        {:ok, %Response{content: "r2"}}
      ])

      TestProvider.chat(messages1, opts1)
      TestProvider.chat(messages2, opts2)

      calls = TestProvider.get_calls(self())
      assert length(calls) == 2
      assert Enum.at(calls, 0) == {messages1, opts1}
      assert Enum.at(calls, 1) == {messages2, opts2}
    end

    test "records calls made via handler mode" do
      messages = [%{role: "user", content: "test"}]
      opts = [model: "gpt-4"]

      TestProvider.put_handler(self(), fn _msgs, _opts ->
        {:ok, %Response{content: "handled"}}
      end)

      TestProvider.chat(messages, opts)

      calls = TestProvider.get_calls(self())
      assert length(calls) == 1
      assert hd(calls) == {messages, opts}
    end

    test "call log starts empty" do
      assert TestProvider.get_calls(self()) == []
    end

    test "failed queue exhaustion does not record a call" do
      # No responses queued → :no_more_responses, should not record
      TestProvider.chat([], [])

      assert TestProvider.get_calls(self()) == []
    end
  end

  # ---------------------------------------------------------------------------
  # Task 3: Stream & Async Isolation
  # ---------------------------------------------------------------------------

  describe "stream/3" do
    test "emits one StreamChunk per grapheme then a final stop chunk" do
      content = "Hi!"
      response = %Response{content: content, usage: %{tokens: 3}}
      TestProvider.put_responses(self(), [{:ok, response}])

      test_pid = self()
      collector = fn chunk -> send(test_pid, {:chunk, chunk}) end

      result = TestProvider.stream([], collector, [])

      assert {:ok, ^response} = result

      # Collect all received chunks
      received =
        Enum.reduce_while(1..100, [], fn _, acc ->
          receive do
            {:chunk, chunk} -> {:cont, [chunk | acc]}
          after
            0 -> {:halt, acc}
          end
        end)
        |> Enum.reverse()

      graphemes = String.graphemes(content)
      assert length(received) == length(graphemes) + 1

      content_chunks = Enum.take(received, length(graphemes))

      Enum.zip(graphemes, content_chunks)
      |> Enum.each(fn {grapheme, chunk} ->
        assert %StreamChunk{delta: ^grapheme} = chunk
      end)

      stop_chunk = List.last(received)
      assert %StreamChunk{finish_reason: "stop", usage: %{tokens: 3}} = stop_chunk
    end

    test "propagates error from chat/2 when queue is exhausted" do
      result = TestProvider.stream([], fn _chunk -> :ok end, [])
      assert result == {:error, :no_more_responses}
    end
  end

  describe "async isolation" do
    test "two concurrent tasks have independent state" do
      pid_a = self()

      task_b =
        Task.async(fn ->
          {:ok, _} = TestProvider.start_state(self())

          TestProvider.put_responses(self(), [{:ok, %Response{content: "from B"}}])
          result = TestProvider.chat([], [])
          TestProvider.stop_state(self())
          result
        end)

      TestProvider.put_responses(pid_a, [{:ok, %Response{content: "from A"}}])

      result_a = TestProvider.chat([], [])
      result_b = Task.await(task_b)

      assert {:ok, %Response{content: "from A"}} = result_a
      assert {:ok, %Response{content: "from B"}} = result_b
    end

    test "stopping one process state does not affect another" do
      task =
        Task.async(fn ->
          {:ok, _} = TestProvider.start_state(self())
          TestProvider.put_responses(self(), [{:ok, %Response{content: "task response"}}])
          result = TestProvider.chat([], [])
          TestProvider.stop_state(self())
          result
        end)

      TestProvider.put_responses(self(), [{:ok, %Response{content: "main response"}}])

      result_task = Task.await(task)
      result_main = TestProvider.chat([], [])

      assert {:ok, %Response{content: "task response"}} = result_task
      assert {:ok, %Response{content: "main response"}} = result_main
    end
  end
end
