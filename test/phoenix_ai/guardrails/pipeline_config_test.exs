defmodule PhoenixAI.Guardrails.PipelineConfigTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Guardrails.Pipeline
  alias PhoenixAI.Guardrails.Policies.{ContentFilter, JailbreakDetection}

  describe "from_config/1 with preset" do
    test "resolves :default preset" do
      assert {:ok, policies} = Pipeline.from_config(preset: :default)
      assert [{JailbreakDetection, []}] = policies
    end

    test "resolves :strict preset" do
      assert {:ok, policies} = Pipeline.from_config(preset: :strict)
      assert length(policies) == 3
    end

    test "resolves :permissive preset" do
      assert {:ok, policies} = Pipeline.from_config(preset: :permissive)
      assert [{JailbreakDetection, opts}] = policies
      assert opts[:threshold] == 0.9
    end

    test "applies jailbreak_threshold override to preset" do
      assert {:ok, [{JailbreakDetection, opts}]} =
               Pipeline.from_config(preset: :default, jailbreak_threshold: 0.5)

      assert opts[:threshold] == 0.5
    end

    test "applies jailbreak_scope override to preset" do
      assert {:ok, [{JailbreakDetection, opts}]} =
               Pipeline.from_config(preset: :default, jailbreak_scope: :all_user_messages)

      assert opts[:scope] == :all_user_messages
    end

    test "applies jailbreak_detector override to preset" do
      assert {:ok, [{JailbreakDetection, opts}]} =
               Pipeline.from_config(preset: :default, jailbreak_detector: MyCustomDetector)

      assert opts[:detector] == MyCustomDetector
    end
  end

  describe "from_config/1 with explicit policies" do
    test "returns policies as-is" do
      explicit = [{JailbreakDetection, [threshold: 0.5]}, {ContentFilter, []}]

      assert {:ok, ^explicit} = Pipeline.from_config(policies: explicit)
    end
  end

  describe "from_config/1 with empty opts" do
    test "returns empty policy list" do
      assert {:ok, []} = Pipeline.from_config([])
    end
  end

  describe "from_config/1 validation errors" do
    test "invalid preset returns error" do
      assert {:error, %NimbleOptions.ValidationError{}} =
               Pipeline.from_config(preset: :unknown)
    end

    test "invalid jailbreak_threshold type returns error" do
      assert {:error, %NimbleOptions.ValidationError{}} =
               Pipeline.from_config(preset: :default, jailbreak_threshold: "high")
    end

    test "invalid jailbreak_scope returns error" do
      assert {:error, %NimbleOptions.ValidationError{}} =
               Pipeline.from_config(preset: :default, jailbreak_scope: :invalid)
    end
  end

  describe "from_config/1 full integration" do
    test "from_config output works with Pipeline.run/2" do
      alias PhoenixAI.Guardrails.Request
      alias PhoenixAI.Message

      request = %Request{messages: [%Message{role: :user, content: "Hello world"}]}

      assert {:ok, policies} = Pipeline.from_config(preset: :default)
      assert {:ok, ^request} = Pipeline.run(policies, request)
    end
  end
end
