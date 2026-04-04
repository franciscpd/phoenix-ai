defmodule PhoenixAI.Guardrails.Policies.ContentFilterTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Guardrails.Policies.ContentFilter
  alias PhoenixAI.Guardrails.{PolicyViolation, Request}
  alias PhoenixAI.Message

  defp build_request(content \\ "Hello") do
    %Request{messages: [%Message{role: :user, content: content}]}
  end

  describe "check/2 with no hooks" do
    test "passes request through unchanged" do
      request = build_request()
      assert {:ok, ^request} = ContentFilter.check(request, [])
    end
  end

  describe "check/2 with :pre hook" do
    test "passes when pre hook returns {:ok, request}" do
      request = build_request()
      pre = fn req -> {:ok, %{req | assigns: Map.put(req.assigns, :filtered, true)}} end
      assert {:ok, result} = ContentFilter.check(request, pre: pre)
      assert result.assigns.filtered == true
    end

    test "halts when pre hook returns {:error, reason}" do
      request = build_request("bad content")
      pre = fn _req -> {:error, "Profanity detected"} end
      assert {:halt, %PolicyViolation{} = violation} = ContentFilter.check(request, pre: pre)
      assert violation.policy == ContentFilter
      assert violation.reason == "Profanity detected"
    end
  end

  describe "check/2 with :post hook" do
    test "passes when post hook returns {:ok, request}" do
      request = build_request()
      post = fn req -> {:ok, %{req | assigns: Map.put(req.assigns, :validated, true)}} end
      assert {:ok, result} = ContentFilter.check(request, post: post)
      assert result.assigns.validated == true
    end

    test "halts when post hook returns {:error, reason}" do
      request = build_request()
      post = fn _req -> {:error, "Output validation failed"} end
      assert {:halt, %PolicyViolation{} = violation} = ContentFilter.check(request, post: post)
      assert violation.reason == "Output validation failed"
    end
  end

  describe "check/2 with both :pre and :post hooks" do
    test "pre modifies request, post receives modified request" do
      request = build_request()
      pre = fn req -> {:ok, %{req | assigns: Map.put(req.assigns, :sanitized, true)}} end

      post = fn req ->
        assert req.assigns.sanitized == true
        {:ok, %{req | assigns: Map.put(req.assigns, :validated, true)}}
      end

      assert {:ok, result} = ContentFilter.check(request, pre: pre, post: post)
      assert result.assigns.sanitized == true
      assert result.assigns.validated == true
    end

    test "pre rejects — post never runs" do
      request = build_request()
      pre = fn _req -> {:error, "Blocked by pre"} end
      post = fn _req -> raise "post should not be called" end

      assert {:halt, %PolicyViolation{reason: "Blocked by pre"}} =
               ContentFilter.check(request, pre: pre, post: post)
    end
  end
end
