defmodule PhoenixAI.Guardrails.PipelinePresetTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Guardrails.Pipeline
  alias PhoenixAI.Guardrails.Policies.{ContentFilter, JailbreakDetection, ToolPolicy}

  describe "preset/1" do
    test ":default returns JailbreakDetection only" do
      assert [{JailbreakDetection, []}] = Pipeline.preset(:default)
    end

    test ":strict returns all three policies" do
      policies = Pipeline.preset(:strict)
      assert length(policies) == 3
      assert {JailbreakDetection, []} in policies
      assert {ContentFilter, []} in policies
      assert {ToolPolicy, []} in policies
    end

    test ":permissive returns JailbreakDetection with high threshold" do
      assert [{JailbreakDetection, opts}] = Pipeline.preset(:permissive)
      assert opts[:threshold] == 0.9
    end

    test "preset output works with Pipeline.run/2" do
      alias PhoenixAI.Guardrails.Request
      alias PhoenixAI.Message

      request = %Request{messages: [%Message{role: :user, content: "Hello world"}]}
      policies = Pipeline.preset(:default)

      assert {:ok, ^request} = Pipeline.run(policies, request)
    end
  end
end
