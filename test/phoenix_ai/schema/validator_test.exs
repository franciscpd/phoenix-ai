defmodule PhoenixAI.Schema.ValidatorTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Schema.Validator

  @simple_schema %{
    type: :object,
    properties: %{
      name: %{type: :string},
      age: %{type: :integer}
    },
    required: [:name, :age]
  }

  describe "validate/2 — required keys" do
    test "passes when all required keys present" do
      data = %{"name" => "Alice", "age" => 30}
      assert :ok = Validator.validate(data, @simple_schema)
    end

    test "fails when required key is missing" do
      data = %{"name" => "Alice"}
      assert {:error, details} = Validator.validate(data, @simple_schema)
      assert "age" in details.missing_keys
    end

    test "fails when multiple required keys missing" do
      data = %{}
      assert {:error, details} = Validator.validate(data, @simple_schema)
      assert Enum.sort(details.missing_keys) == ["age", "name"]
    end

    test "passes when no required keys defined" do
      schema = %{type: :object, properties: %{name: %{type: :string}}}
      assert :ok = Validator.validate(%{"name" => "Alice"}, schema)
    end

    test "passes with extra keys not in schema" do
      data = %{"name" => "Alice", "age" => 30, "extra" => "value"}
      assert :ok = Validator.validate(data, @simple_schema)
    end
  end

  describe "validate/2 — type checking" do
    test "validates string type" do
      schema = %{type: :object, properties: %{name: %{type: :string}}, required: [:name]}
      assert :ok = Validator.validate(%{"name" => "Alice"}, schema)
      assert {:error, details} = Validator.validate(%{"name" => 123}, schema)
      assert [%{key: "name", expected: "string"}] = details.type_errors
    end

    test "validates number type" do
      schema = %{type: :object, properties: %{score: %{type: :number}}, required: [:score]}
      assert :ok = Validator.validate(%{"score" => 3.14}, schema)
      assert :ok = Validator.validate(%{"score" => 42}, schema)
      assert {:error, details} = Validator.validate(%{"score" => "high"}, schema)
      assert [%{key: "score", expected: "number"}] = details.type_errors
    end

    test "validates integer type" do
      schema = %{type: :object, properties: %{count: %{type: :integer}}, required: [:count]}
      assert :ok = Validator.validate(%{"count" => 42}, schema)
      assert {:error, details} = Validator.validate(%{"count" => 3.14}, schema)
      assert [%{key: "count", expected: "integer"}] = details.type_errors
    end

    test "validates boolean type" do
      schema = %{type: :object, properties: %{active: %{type: :boolean}}, required: [:active]}
      assert :ok = Validator.validate(%{"active" => true}, schema)
      assert {:error, details} = Validator.validate(%{"active" => "yes"}, schema)
      assert [%{key: "active", expected: "boolean"}] = details.type_errors
    end

    test "validates array type" do
      schema = %{type: :object, properties: %{tags: %{type: :array}}, required: [:tags]}
      assert :ok = Validator.validate(%{"tags" => ["a", "b"]}, schema)
      assert {:error, details} = Validator.validate(%{"tags" => "not_array"}, schema)
      assert [%{key: "tags", expected: "array"}] = details.type_errors
    end

    test "validates object type" do
      schema = %{type: :object, properties: %{meta: %{type: :object}}, required: [:meta]}
      assert :ok = Validator.validate(%{"meta" => %{"k" => "v"}}, schema)
      assert {:error, details} = Validator.validate(%{"meta" => "string"}, schema)
      assert [%{key: "meta", expected: "object"}] = details.type_errors
    end

    test "skips type check for optional keys that are absent" do
      schema = %{type: :object, properties: %{name: %{type: :string}}}
      assert :ok = Validator.validate(%{}, schema)
    end
  end

  describe "validate/2 — enum" do
    test "passes when value is in enum" do
      schema = %{
        type: :object,
        properties: %{color: %{type: :string, enum: [:red, :green, :blue]}},
        required: [:color]
      }

      assert :ok = Validator.validate(%{"color" => "red"}, schema)
    end

    test "fails when value is not in enum" do
      schema = %{
        type: :object,
        properties: %{color: %{type: :string, enum: [:red, :green, :blue]}},
        required: [:color]
      }

      assert {:error, details} = Validator.validate(%{"color" => "yellow"}, schema)

      assert [%{key: "color", expected: ["red", "green", "blue"], got: "yellow"}] =
               details.enum_errors
    end
  end

  describe "validate/2 — nested objects" do
    test "validates nested object properties recursively" do
      schema = %{
        type: :object,
        properties: %{
          address: %{
            type: :object,
            properties: %{
              city: %{type: :string},
              zip: %{type: :string}
            },
            required: [:city]
          }
        },
        required: [:address]
      }

      assert :ok = Validator.validate(%{"address" => %{"city" => "Lisbon"}}, schema)
    end

    test "reports nested validation errors with path" do
      schema = %{
        type: :object,
        properties: %{
          address: %{
            type: :object,
            properties: %{city: %{type: :string}},
            required: [:city]
          }
        },
        required: [:address]
      }

      assert {:error, details} = Validator.validate(%{"address" => %{}}, schema)
      assert "address.city" in details.missing_keys
    end
  end

  describe "validate/2 — combined errors" do
    test "reports multiple error types at once" do
      schema = %{
        type: :object,
        properties: %{
          name: %{type: :string},
          age: %{type: :integer},
          status: %{type: :string, enum: [:active, :inactive]}
        },
        required: [:name, :age, :status]
      }

      data = %{"age" => "thirty", "status" => "unknown"}

      assert {:error, details} = Validator.validate(data, schema)
      assert "name" in details.missing_keys
      assert length(details.type_errors) == 1
      assert length(details.enum_errors) == 1
    end
  end

  describe "validate/2 — edge cases" do
    test "empty schema passes anything" do
      assert :ok = Validator.validate(%{"any" => "data"}, %{})
    end

    test "nil values pass type checks (nullable)" do
      schema = %{type: :object, properties: %{name: %{type: :string}}, required: [:name]}
      assert :ok = Validator.validate(%{"name" => nil}, schema)
    end
  end
end
