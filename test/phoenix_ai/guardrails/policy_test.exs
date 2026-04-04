defmodule PhoenixAI.Guardrails.PolicyTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Guardrails.{PolicyViolation, Request}
  alias PhoenixAI.Message

  describe "behaviour compliance" do
    test "module implementing check/2 satisfies the behaviour" do
      defmodule PassPolicy do
        @behaviour PhoenixAI.Guardrails.Policy

        @impl true
        def check(request, _opts), do: {:ok, request}
      end

      request = %Request{messages: [%Message{role: :user, content: "Hello"}]}
      assert {:ok, ^request} = PassPolicy.check(request, [])
    end

    test "module returning {:halt, violation} satisfies the behaviour" do
      defmodule HaltPolicy do
        @behaviour PhoenixAI.Guardrails.Policy

        @impl true
        def check(_request, _opts) do
          {:halt, %PolicyViolation{policy: __MODULE__, reason: "Blocked"}}
        end
      end

      request = %Request{messages: [%Message{role: :user, content: "Hello"}]}

      assert {:halt, %PolicyViolation{policy: HaltPolicy, reason: "Blocked"}} =
               HaltPolicy.check(request, [])
    end
  end

  describe "Mox mock" do
    test "MockPolicy can be defined and used" do
      assert Code.ensure_loaded?(PhoenixAI.Guardrails.MockPolicy)
    end
  end
end
