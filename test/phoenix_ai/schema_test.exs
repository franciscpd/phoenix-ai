defmodule PhoenixAI.SchemaTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Schema

  describe "resolve/1 with plain map" do
    test "converts atom keys to string keys" do
      schema = %{type: :object, properties: %{name: %{type: :string}}, required: [:name]}
      result = Schema.resolve(schema)

      assert result == %{
               "type" => "object",
               "properties" => %{"name" => %{"type" => "string"}},
               "required" => ["name"]
             }
    end

    test "handles nested objects" do
      schema = %{
        type: :object,
        properties: %{
          address: %{
            type: :object,
            properties: %{city: %{type: :string}},
            required: [:city]
          }
        }
      }

      result = Schema.resolve(schema)
      assert result["properties"]["address"]["properties"]["city"]["type"] == "string"
      assert result["properties"]["address"]["required"] == ["city"]
    end

    test "preserves string values and numbers" do
      schema = %{type: :object, properties: %{name: %{type: :string, description: "The name"}}}
      result = Schema.resolve(schema)
      assert result["properties"]["name"]["description"] == "The name"
    end

    test "handles boolean values without converting" do
      schema = %{type: :object, additionalProperties: false}
      result = Schema.resolve(schema)
      assert result["additionalProperties"] == false
    end
  end

  describe "resolve/1 with behaviour module" do
    test "calls schema/0 and converts to string keys" do
      result = Schema.resolve(PhoenixAI.TestSchemas.SentimentSchema)

      assert result == %{
               "type" => "object",
               "properties" => %{
                 "sentiment" => %{
                   "type" => "string",
                   "enum" => ["positive", "negative", "neutral"]
                 },
                 "confidence" => %{"type" => "number"}
               },
               "required" => ["sentiment", "confidence"]
             }
    end
  end

  describe "schema_map/1" do
    test "returns atom-keyed map from module" do
      result = Schema.schema_map(PhoenixAI.TestSchemas.SentimentSchema)
      assert result[:type] == :object
      assert result[:required] == [:sentiment, :confidence]
    end

    test "returns map as-is for plain maps" do
      schema = %{type: :object, properties: %{name: %{type: :string}}}
      assert Schema.schema_map(schema) == schema
    end
  end
end
