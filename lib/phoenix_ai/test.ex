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
