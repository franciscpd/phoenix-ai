defmodule PhoenixAI.Schema.ValidateResponseTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.{Response, Schema}

  @schema %{
    type: :object,
    properties: %{
      name: %{type: :string},
      age: %{type: :integer}
    },
    required: [:name, :age]
  }

  describe "validate_response/3" do
    test "decodes valid JSON and populates parsed" do
      response = %Response{content: ~s({"name":"Alice","age":30})}

      assert {:ok, %Response{parsed: %{"name" => "Alice", "age" => 30}}} =
               Schema.validate_response(response, @schema, @schema)
    end

    test "preserves original content as raw JSON string" do
      json = ~s({"name":"Alice","age":30})
      response = %Response{content: json}
      {:ok, result} = Schema.validate_response(response, @schema, @schema)
      assert result.content == json
    end

    test "returns invalid_json when content is not JSON" do
      response = %Response{content: "Hello, I'm not JSON"}

      assert {:error, {:invalid_json, "Hello, I'm not JSON"}} =
               Schema.validate_response(response, @schema, @schema)
    end

    test "returns validation_failed when JSON doesn't match schema" do
      response = %Response{content: ~s({"name":"Alice"})}

      assert {:error, {:validation_failed, details}} =
               Schema.validate_response(response, @schema, @schema)

      assert "age" in details.missing_keys
    end

    test "returns validation_failed for type mismatch" do
      response = %Response{content: ~s({"name":123,"age":30})}

      assert {:error, {:validation_failed, details}} =
               Schema.validate_response(response, @schema, @schema)

      assert [%{key: "name", expected: "string"}] = details.type_errors
    end

    test "calls cast/1 when schema is a module with cast implemented" do
      defmodule CastSchema do
        @behaviour PhoenixAI.Schema
        @impl true
        def schema, do: %{type: :object, properties: %{val: %{type: :integer}}, required: [:val]}
        @impl true
        def cast(%{"val" => v}), do: {:ok, %{value: v * 2}}
      end

      response = %Response{content: ~s({"val":21})}

      assert {:ok, %Response{parsed: %{value: 42}}} =
               Schema.validate_response(
                 response,
                 %{type: :object, properties: %{val: %{type: :integer}}, required: [:val]},
                 CastSchema
               )
    end

    test "returns cast_failed when cast/1 returns error" do
      defmodule FailCastSchema do
        @behaviour PhoenixAI.Schema
        @impl true
        def schema, do: %{type: :object, properties: %{val: %{type: :integer}}, required: [:val]}
        @impl true
        def cast(_), do: {:error, :custom_error}
      end

      response = %Response{content: ~s({"val":1})}

      assert {:error, {:cast_failed, :custom_error}} =
               Schema.validate_response(
                 response,
                 %{type: :object, properties: %{val: %{type: :integer}}, required: [:val]},
                 FailCastSchema
               )
    end

    test "skips cast when schema is a plain map" do
      response = %Response{content: ~s({"name":"Alice","age":30})}
      {:ok, result} = Schema.validate_response(response, @schema, @schema)
      assert result.parsed == %{"name" => "Alice", "age" => 30}
    end

    test "returns invalid_json when content is nil" do
      response = %Response{content: nil}

      assert {:error, {:invalid_json, nil}} =
               Schema.validate_response(response, @schema, @schema)
    end
  end
end
