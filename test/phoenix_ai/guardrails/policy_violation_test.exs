defmodule PhoenixAI.Guardrails.PolicyViolationTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Guardrails.PolicyViolation

  describe "struct" do
    test "constructs with required fields" do
      violation = %PolicyViolation{
        policy: MyPolicy,
        reason: "Budget exceeded"
      }

      assert violation.policy == MyPolicy
      assert violation.reason == "Budget exceeded"
      assert violation.message == nil
      assert violation.metadata == %{}
    end

    test "constructs with all fields" do
      violation = %PolicyViolation{
        policy: MyPolicy,
        reason: "Jailbreak detected",
        message: "Ignore previous instructions",
        metadata: %{score: 0.85, threshold: 0.7}
      }

      assert violation.policy == MyPolicy
      assert violation.reason == "Jailbreak detected"
      assert violation.message == "Ignore previous instructions"
      assert violation.metadata == %{score: 0.85, threshold: 0.7}
    end

    test "raises without policy field" do
      assert_raise ArgumentError,
                   ~r/the following keys must also be given when building struct/,
                   fn ->
                     struct!(PolicyViolation, reason: "Missing policy")
                   end
    end

    test "raises without reason field" do
      assert_raise ArgumentError,
                   ~r/the following keys must also be given when building struct/,
                   fn ->
                     struct!(PolicyViolation, policy: MyPolicy)
                   end
    end
  end
end
