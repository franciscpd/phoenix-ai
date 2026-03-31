defmodule PhoenixAI.TestHelperTest do
  use ExUnit.Case, async: true
  use PhoenixAI.Test

  alias PhoenixAI.{Message, Response}

  describe "set_responses/1 + AI.chat/2 with provider: :test" do
    test "returns scripted response" do
      set_responses([{:ok, %Response{content: "Hello"}}])

      assert {:ok, %Response{content: "Hello"}} =
               AI.chat([%Message{role: :user, content: "Hi"}],
                 provider: :test,
                 api_key: "test"
               )
    end

    test "returns responses in FIFO order" do
      set_responses([
        {:ok, %Response{content: "first"}},
        {:ok, %Response{content: "second"}}
      ])

      assert {:ok, %Response{content: "first"}} =
               AI.chat([%Message{role: :user, content: "Hi"}],
                 provider: :test,
                 api_key: "test"
               )

      assert {:ok, %Response{content: "second"}} =
               AI.chat([%Message{role: :user, content: "Hi again"}],
                 provider: :test,
                 api_key: "test"
               )
    end
  end

  describe "set_handler/1 + AI.chat/2 with provider: :test" do
    test "uses handler function to produce response" do
      set_handler(fn _messages, _opts ->
        {:ok, %Response{content: "from handler"}}
      end)

      assert {:ok, %Response{content: "from handler"}} =
               AI.chat([%Message{role: :user, content: "Hi"}],
                 provider: :test,
                 api_key: "test"
               )
    end

    test "handler receives messages and opts" do
      test_pid = self()

      set_handler(fn messages, opts ->
        send(test_pid, {:handler_called, messages, opts})
        {:ok, %Response{content: "ok"}}
      end)

      messages = [%Message{role: :user, content: "test"}]
      AI.chat(messages, provider: :test, api_key: "test", model: "test-model")

      assert_received {:handler_called, ^messages, _opts}
    end
  end

  describe "get_calls/0" do
    test "returns call log after AI.chat calls" do
      set_responses([
        {:ok, %Response{content: "r1"}},
        {:ok, %Response{content: "r2"}}
      ])

      messages1 = [%Message{role: :user, content: "first"}]
      messages2 = [%Message{role: :user, content: "second"}]

      AI.chat(messages1, provider: :test, api_key: "test")
      AI.chat(messages2, provider: :test, api_key: "test")

      calls = get_calls()
      assert length(calls) == 2
      assert elem(Enum.at(calls, 0), 0) == messages1
      assert elem(Enum.at(calls, 1), 0) == messages2
    end

    test "call log is empty before any calls" do
      assert get_calls() == []
    end
  end

  describe "assert_called/1" do
    test "passes when a matching call exists" do
      set_responses([{:ok, %Response{content: "ok"}}])
      messages = [%Message{role: :user, content: "Hello"}]
      AI.chat(messages, provider: :test, api_key: "test")

      assert_called({^messages, _opts})
    end

    test "fails when no matching call exists" do
      set_responses([{:ok, %Response{content: "ok"}}])
      AI.chat([%Message{role: :user, content: "Hello"}], provider: :test, api_key: "test")

      assert_raise ExUnit.AssertionError, fn ->
        other = [%Message{role: :user, content: "Goodbye"}]
        assert_called({^other, _opts})
      end
    end

    test "matches with partial patterns" do
      set_responses([{:ok, %Response{content: "ok"}}])
      AI.chat([%Message{role: :user, content: "Hello"}], provider: :test, api_key: "test")

      assert_called({_messages, _opts})
    end
  end

  describe "state cleanup" do
    test "fresh test sees no stale state (verifies on_exit works)" do
      # This test verifies that the setup block gives us a clean state.
      # If on_exit from a previous test left stale state, we would have
      # unexpected calls or responses. A fresh state has empty calls.
      assert get_calls() == []

      # Adding a response and consuming it should not bleed into the next test.
      set_responses([{:ok, %Response{content: "ephemeral"}}])
      AI.chat([%Message{role: :user, content: "Hi"}], provider: :test, api_key: "test")

      # Within this test the call is recorded
      assert length(get_calls()) == 1
    end
  end
end
