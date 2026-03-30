defmodule PhoenixAI.Providers.OpenAIStructuredTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Providers.OpenAI

  describe "build_body/3 with schema_json" do
    test "injects response_format into request body" do
      schema_json = %{
        "type" => "object",
        "properties" => %{"name" => %{"type" => "string"}},
        "required" => ["name"]
      }

      body = OpenAI.build_body("gpt-4o", [], schema_json: schema_json)

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
      body = OpenAI.build_body("gpt-4o", [], [])
      refute Map.has_key?(body, "response_format")
    end

    test "includes tools_json alongside response_format" do
      schema_json = %{"type" => "object"}
      tools_json = [%{"type" => "function", "function" => %{"name" => "foo"}}]

      body = OpenAI.build_body("gpt-4o", [], schema_json: schema_json, tools_json: tools_json)

      assert Map.has_key?(body, "response_format")
      assert body["tools"] == tools_json
    end
  end
end
