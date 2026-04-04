defmodule PhoenixAI.Guardrails.JailbreakDetectorTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Guardrails.JailbreakDetector.DetectionResult

  describe "DetectionResult struct" do
    test "has expected default values" do
      result = %DetectionResult{}
      assert result.score == 0.0
      assert result.patterns == []
      assert result.details == %{}
    end

    test "constructs with all fields" do
      result = %DetectionResult{
        score: 0.85,
        patterns: ["ignore previous"],
        details: %{categories: [:instruction_override]}
      }

      assert result.score == 0.85
      assert result.patterns == ["ignore previous"]
      assert result.details == %{categories: [:instruction_override]}
    end
  end

  describe "behaviour compliance" do
    test "module implementing detect/2 with :safe return satisfies behaviour" do
      defmodule SafeDetector do
        @behaviour PhoenixAI.Guardrails.JailbreakDetector

        @impl true
        def detect(_content, _opts) do
          {:safe, %DetectionResult{}}
        end
      end

      assert {:safe, %DetectionResult{score: 0.0}} = SafeDetector.detect("hello", [])
    end

    test "module implementing detect/2 with :detected return satisfies behaviour" do
      defmodule UnsafeDetector do
        @behaviour PhoenixAI.Guardrails.JailbreakDetector

        @impl true
        def detect(_content, _opts) do
          {:detected, %DetectionResult{score: 0.9, patterns: ["jailbreak"]}}
        end
      end

      assert {:detected, %DetectionResult{score: 0.9}} = UnsafeDetector.detect("bad", [])
    end
  end

  describe "Mox mock" do
    test "MockDetector is available" do
      assert Code.ensure_loaded?(PhoenixAI.Guardrails.MockDetector)
    end
  end
end
