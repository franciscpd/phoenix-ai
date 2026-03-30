defmodule PhoenixAI.Providers.OpenRouterStructuredTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Providers.OpenRouter

  describe "build_body/3 with schema_json" do
    test "injects response_format into request body" do
      schema_json = %{
        "type" => "object",
        "properties" => %{"name" => %{"type" => "string"}},
        "required" => ["name"]
      }

      body = OpenRouter.build_body("anthropic/claude-sonnet-4-5", [], schema_json: schema_json)

      assert body["response_format"] == %{
               "type" => "json_schema",
               "json_schema" => %{
                 "name" => "structured_output",
                 "strict" => true,
                 "schema" => schema_json
               }
             }
    end

    test "does not inject response_format when no schema_json" do
      body = OpenRouter.build_body("anthropic/claude-sonnet-4-5", [], [])
      refute Map.has_key?(body, "response_format")
    end
  end
end
