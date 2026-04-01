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

        test "verifies calls were made" do
          set_responses([{:ok, %Response{content: "Hi"}}])
          AI.chat([%{role: "user", content: "Hello"}], provider: :test, api_key: "test")

          assert_called({[%{role: "user", content: "Hello"}], _opts})
        end
      end
  """

  defmacro __using__(_opts) do
    quote do
      alias PhoenixAI.Providers.TestProvider
      import PhoenixAI.Test, only: [assert_called: 1]

      setup do
        test_pid = self()
        {:ok, _} = TestProvider.start_state(test_pid)
        on_exit(fn -> TestProvider.stop_state(test_pid) end)
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

  @doc """
  Asserts that at least one call to the TestProvider matches the given pattern.

  Uses pattern matching, so you can use `_` and pinned variables.

  ## Examples

      assert_called({[%{role: "user", content: "Hello"}], _opts})
      assert_called({_messages, opts} when opts[:model] == "gpt-4o")
  """
  defmacro assert_called(pattern) do
    quote do
      alias PhoenixAI.Providers.TestProvider
      calls = TestProvider.get_calls(self())

      assert Enum.any?(calls, fn call -> match?(unquote(pattern), call) end),
             "Expected a call matching #{inspect(unquote(Macro.escape(pattern)))}, " <>
               "got #{length(calls)} call(s): #{inspect(calls)}"
    end
  end
end
