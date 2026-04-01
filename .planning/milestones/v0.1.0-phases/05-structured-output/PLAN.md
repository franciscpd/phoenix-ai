# Structured Output Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add structured output support — JSON schemas declared as plain maps or behaviour modules, provider-specific translation, and response validation with field-level errors.

**Architecture:** Centralized validation in `AI.chat/2` after provider returns. Each adapter translates schema to its wire format (OpenAI: `response_format`, Anthropic: synthetic tool_use). A shared `Schema.validate_response/3` helper handles decode → validate → cast for both `AI.chat/2` and `Agent`.

**Tech Stack:** Elixir, Jason (JSON decode), Mox (testing), existing PhoenixAI provider architecture.

**Spec:** `.planning/phases/05-structured-output/BRAINSTORM.md`

---

### Task 1: Response struct — add `parsed` field

**Files:**
- Modify: `lib/phoenix_ai/response.ex`
- Modify: `test/phoenix_ai/response_test.exs`

- [ ] **Step 1: Write the failing test**

In `test/phoenix_ai/response_test.exs`, add:

```elixir
test "includes parsed field defaulting to nil" do
  response = %PhoenixAI.Response{}
  assert Map.has_key?(response, :parsed)
  assert response.parsed == nil
end

test "parsed can hold a map" do
  response = %PhoenixAI.Response{parsed: %{"name" => "Alice"}}
  assert response.parsed == %{"name" => "Alice"}
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/phoenix_ai/response_test.exs --trace`
Expected: FAIL — `parsed` key does not exist on struct.

- [ ] **Step 3: Add parsed field to Response struct**

In `lib/phoenix_ai/response.ex`, update the struct and typespec:

```elixir
@type t :: %__MODULE__{
        content: String.t() | nil,
        parsed: map() | nil,
        tool_calls: [PhoenixAI.ToolCall.t()],
        usage: map(),
        finish_reason: String.t() | nil,
        model: String.t() | nil,
        provider_response: map()
      }

defstruct [:content, :parsed, :finish_reason, :model, tool_calls: [], usage: %{}, provider_response: %{}]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/phoenix_ai/response_test.exs --trace`
Expected: PASS

- [ ] **Step 5: Run full test suite for regressions**

Run: `mix test`
Expected: All existing tests pass. The new `parsed: nil` default is backward compatible.

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_ai/response.ex test/phoenix_ai/response_test.exs
git commit -m "feat(05): add parsed field to Response struct"
```

---

### Task 2: Schema behaviour and resolve/1

**Files:**
- Create: `lib/phoenix_ai/schema.ex`
- Create: `test/phoenix_ai/schema_test.exs`
- Create: `test/support/schemas/sentiment_schema.ex`

- [ ] **Step 1: Create test support schema module**

Create `test/support/schemas/sentiment_schema.ex`:

```elixir
defmodule PhoenixAI.TestSchemas.SentimentSchema do
  @behaviour PhoenixAI.Schema

  @impl true
  def schema do
    %{
      type: :object,
      properties: %{
        sentiment: %{type: :string, enum: [:positive, :negative, :neutral]},
        confidence: %{type: :number}
      },
      required: [:sentiment, :confidence]
    }
  end
end
```

- [ ] **Step 2: Write failing tests for Schema module**

Create `test/phoenix_ai/schema_test.exs`:

```elixir
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
```

- [ ] **Step 3: Run test to verify it fails**

Run: `mix test test/phoenix_ai/schema_test.exs --trace`
Expected: FAIL — `PhoenixAI.Schema` module does not exist.

- [ ] **Step 4: Implement Schema module**

Create `lib/phoenix_ai/schema.ex`:

```elixir
defmodule PhoenixAI.Schema do
  @moduledoc """
  Behaviour for defining structured output schemas.

  Schemas can be plain Elixir maps (atom keys, JSON Schema structure) or
  modules implementing this behaviour. Both produce identical provider output.

  ## Plain map usage

      AI.chat(messages, schema: %{
        type: :object,
        properties: %{name: %{type: :string}},
        required: [:name]
      })

  ## Behaviour module usage

      defmodule MyApp.Sentiment do
        @behaviour PhoenixAI.Schema

        @impl true
        def schema do
          %{
            type: :object,
            properties: %{
              sentiment: %{type: :string, enum: [:positive, :negative, :neutral]},
              confidence: %{type: :number}
            },
            required: [:sentiment, :confidence]
          }
        end
      end

      AI.chat(messages, schema: MyApp.Sentiment)
  """

  @callback schema() :: map()
  @callback cast(data :: map()) :: {:ok, term()} | {:error, term()}

  @optional_callbacks [cast: 1]

  @doc """
  Resolves a schema (module or map) to a string-keyed JSON Schema map.

  Modules have their `schema/0` callback called first, then atom keys
  are converted to strings.
  """
  @spec resolve(module() | map()) :: map()
  def resolve(mod) when is_atom(mod), do: deep_stringify(mod.schema())
  def resolve(map) when is_map(map), do: deep_stringify(map)

  @doc """
  Returns the raw atom-keyed schema map. For modules, calls `schema/0`.
  For maps, returns as-is. Used for validation (which operates on atom keys).
  """
  @spec schema_map(module() | map()) :: map()
  def schema_map(mod) when is_atom(mod), do: mod.schema()
  def schema_map(map) when is_map(map), do: map

  defp deep_stringify(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {stringify_key(k), deep_stringify(v)} end)
  end

  defp deep_stringify(list) when is_list(list) do
    Enum.map(list, &deep_stringify/1)
  end

  defp deep_stringify(atom) when is_atom(atom) and not is_boolean(atom) and not is_nil(atom) do
    Atom.to_string(atom)
  end

  defp deep_stringify(other), do: other

  defp stringify_key(key) when is_atom(key), do: Atom.to_string(key)
  defp stringify_key(key), do: key
end
```

- [ ] **Step 5: Run test to verify it passes**

Run: `mix test test/phoenix_ai/schema_test.exs --trace`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_ai/schema.ex test/phoenix_ai/schema_test.exs test/support/schemas/sentiment_schema.ex
git commit -m "feat(05): add Schema behaviour with dual map/module resolve"
```

---

### Task 3: Schema.Validator — pure validation

**Files:**
- Create: `lib/phoenix_ai/schema/validator.ex`
- Create: `test/phoenix_ai/schema/validator_test.exs`

- [ ] **Step 1: Write failing tests for Validator**

Create `test/phoenix_ai/schema/validator_test.exs`:

```elixir
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
      assert [%{key: "color", expected: ["red", "green", "blue"], got: "yellow"}] = details.enum_errors
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/phoenix_ai/schema/validator_test.exs --trace`
Expected: FAIL — `PhoenixAI.Schema.Validator` module does not exist.

- [ ] **Step 3: Implement Validator module**

Create `lib/phoenix_ai/schema/validator.ex`:

```elixir
defmodule PhoenixAI.Schema.Validator do
  @moduledoc """
  Pure-function JSON Schema validator.

  Validates decoded JSON data against an atom-keyed schema map.
  Supports required keys, basic types, enum values, and recursive nested objects.
  """

  @type error_details :: %{
          missing_keys: [String.t()],
          type_errors: [%{key: String.t(), expected: String.t(), got: String.t(), value: term()}],
          enum_errors: [%{key: String.t(), expected: [String.t()], got: String.t()}]
        }

  @doc """
  Validates `data` against `schema`.

  Returns `:ok` or `{:error, details}` with field-level information.
  """
  @spec validate(map(), map()) :: :ok | {:error, error_details()}
  def validate(data, schema) do
    validate_object(data, schema, "")
  end

  defp validate_object(data, schema, prefix) do
    properties = Map.get(schema, :properties, %{})
    required = Map.get(schema, :required, [])

    missing = check_required(data, required, prefix)
    {type_errors, enum_errors} = check_properties(data, properties, prefix)

    case {missing, type_errors, enum_errors} do
      {[], [], []} -> :ok
      _ -> {:error, %{missing_keys: missing, type_errors: type_errors, enum_errors: enum_errors}}
    end
  end

  defp check_required(data, required, prefix) do
    Enum.reduce(required, [], fn key, acc ->
      str_key = Atom.to_string(key)

      if Map.has_key?(data, str_key) do
        acc
      else
        [prefixed(prefix, str_key) | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp check_properties(data, properties, prefix) do
    Enum.reduce(properties, {[], []}, fn {key, prop_schema}, {type_acc, enum_acc} ->
      str_key = Atom.to_string(key)
      full_key = prefixed(prefix, str_key)

      case Map.fetch(data, str_key) do
        :error ->
          {type_acc, enum_acc}

        {:ok, nil} ->
          {type_acc, enum_acc}

        {:ok, value} ->
          type_acc = check_type(value, prop_schema, full_key, type_acc)
          enum_acc = check_enum(value, prop_schema, full_key, enum_acc)

          # Recurse into nested objects
          {nested_type, nested_enum} =
            if prop_schema[:type] == :object and is_map(value) do
              case validate_object(value, prop_schema, full_key) do
                :ok -> {[], []}
                {:error, nested} -> {nested.type_errors, nested.enum_errors}
              end
            else
              {[], []}
            end

          # For nested missing keys, we need to merge them differently
          {type_acc ++ nested_type, enum_acc ++ nested_enum}
      end
    end)
  end

  defp check_type(value, prop_schema, key, acc) do
    type = prop_schema[:type]

    if type && !matches_type?(value, type) do
      [%{key: key, expected: Atom.to_string(type), got: type_name(value), value: value} | acc]
    else
      acc
    end
  end

  defp check_enum(value, prop_schema, key, acc) do
    case prop_schema[:enum] do
      nil ->
        acc

      allowed ->
        str_allowed = Enum.map(allowed, &to_string/1)

        if to_string(value) in str_allowed do
          acc
        else
          [%{key: key, expected: str_allowed, got: to_string(value)} | acc]
        end
    end
  end

  defp matches_type?(value, :string), do: is_binary(value)
  defp matches_type?(value, :number), do: is_number(value)
  defp matches_type?(value, :integer), do: is_integer(value)
  defp matches_type?(value, :boolean), do: is_boolean(value)
  defp matches_type?(value, :array), do: is_list(value)
  defp matches_type?(value, :object), do: is_map(value)
  defp matches_type?(_value, _type), do: true

  defp type_name(v) when is_binary(v), do: "string"
  defp type_name(v) when is_integer(v), do: "integer"
  defp type_name(v) when is_float(v), do: "number"
  defp type_name(v) when is_boolean(v), do: "boolean"
  defp type_name(v) when is_list(v), do: "array"
  defp type_name(v) when is_map(v), do: "object"
  defp type_name(_), do: "unknown"

  defp prefixed("", key), do: key
  defp prefixed(prefix, key), do: "#{prefix}.#{key}"
end
```

Note: The `validate_object` function needs to handle nested missing_keys properly. Let me adjust — when recursing into nested objects, missing keys from the nested call also need to bubble up:

Replace the `check_properties` function body's reduce to also collect nested missing keys. Actually, the cleaner approach is to flatten all errors. Let me revise:

```elixir
defp check_properties(data, properties, prefix) do
  Enum.reduce(properties, {[], []}, fn {key, prop_schema}, {type_acc, enum_acc} ->
    str_key = Atom.to_string(key)
    full_key = prefixed(prefix, str_key)

    case Map.fetch(data, str_key) do
      :error ->
        {type_acc, enum_acc}

      {:ok, nil} ->
        {type_acc, enum_acc}

      {:ok, value} ->
        type_acc = check_type(value, prop_schema, full_key, type_acc)
        enum_acc = check_enum(value, prop_schema, full_key, enum_acc)

        if prop_schema[:type] == :object and is_map(value) do
          case validate_object(value, prop_schema, full_key) do
            :ok -> {type_acc, enum_acc}
            {:error, nested} -> {type_acc ++ nested.type_errors, enum_acc ++ nested.enum_errors}
          end
        else
          {type_acc, enum_acc}
        end
    end
  end)
end
```

And `validate_object` must also collect nested missing keys. The simplest approach is to return all three lists and merge at the top:

The implementation should actually collect all three error lists (missing, type, enum) through the recursion. Here is the corrected `validate_object`:

```elixir
defp validate_object(data, schema, prefix) do
  properties = Map.get(schema, :properties, %{})
  required = Map.get(schema, :required, [])

  missing = check_required(data, required, prefix)
  {type_errors, enum_errors, nested_missing} = check_properties(data, properties, prefix)

  all_missing = missing ++ nested_missing

  case {all_missing, type_errors, enum_errors} do
    {[], [], []} -> :ok
    _ -> {:error, %{missing_keys: all_missing, type_errors: type_errors, enum_errors: enum_errors}}
  end
end
```

And `check_properties` returns a 3-tuple:

```elixir
defp check_properties(data, properties, prefix) do
  Enum.reduce(properties, {[], [], []}, fn {key, prop_schema}, {type_acc, enum_acc, miss_acc} ->
    str_key = Atom.to_string(key)
    full_key = prefixed(prefix, str_key)

    case Map.fetch(data, str_key) do
      :error ->
        {type_acc, enum_acc, miss_acc}

      {:ok, nil} ->
        {type_acc, enum_acc, miss_acc}

      {:ok, value} ->
        type_acc = check_type(value, prop_schema, full_key, type_acc)
        enum_acc = check_enum(value, prop_schema, full_key, enum_acc)

        if prop_schema[:type] == :object and is_map(value) do
          case validate_object(value, prop_schema, full_key) do
            :ok -> {type_acc, enum_acc, miss_acc}
            {:error, nested} ->
              {type_acc ++ nested.type_errors, enum_acc ++ nested.enum_errors, miss_acc ++ nested.missing_keys}
          end
        else
          {type_acc, enum_acc, miss_acc}
        end
    end
  end)
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/phoenix_ai/schema/validator_test.exs --trace`
Expected: PASS — all validation tests green.

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_ai/schema/validator.ex test/phoenix_ai/schema/validator_test.exs
git commit -m "feat(05): add Schema.Validator with type, required, enum, nested checks"
```

---

### Task 4: Schema.validate_response/3 — shared decode + validate + cast helper

**Files:**
- Modify: `lib/phoenix_ai/schema.ex`
- Create: `test/phoenix_ai/schema_validate_response_test.exs`

- [ ] **Step 1: Write failing tests**

Create `test/phoenix_ai/schema_validate_response_test.exs`:

```elixir
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
               Schema.validate_response(response, %{type: :object, properties: %{val: %{type: :integer}}, required: [:val]}, CastSchema)
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
               Schema.validate_response(response, %{type: :object, properties: %{val: %{type: :integer}}, required: [:val]}, FailCastSchema)
    end

    test "skips cast when schema is a plain map" do
      response = %Response{content: ~s({"name":"Alice","age":30})}
      {:ok, result} = Schema.validate_response(response, @schema, @schema)
      assert result.parsed == %{"name" => "Alice", "age" => 30}
    end

    test "returns nil content response unchanged when content is nil" do
      response = %Response{content: nil}
      assert {:error, {:invalid_json, nil}} =
               Schema.validate_response(response, @schema, @schema)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/phoenix_ai/schema_validate_response_test.exs --trace`
Expected: FAIL — `validate_response/3` not defined.

- [ ] **Step 3: Implement validate_response/3 in Schema module**

Add to `lib/phoenix_ai/schema.ex`:

```elixir
alias PhoenixAI.{Response, Schema.Validator}

@doc """
Decodes JSON content from a Response, validates against the schema,
optionally casts via the module's `cast/1`, and returns the Response
with the `parsed` field populated.

The `atom_schema` is the original atom-keyed schema for validation.
The `schema_input` is the original input to `AI.chat` `:schema` option —
either a map or a module. Used to check for `cast/1`.

Returns:
- `{:ok, %Response{parsed: data}}` on success
- `{:error, {:invalid_json, raw_content}}` when content is not valid JSON
- `{:error, {:validation_failed, details}}` when JSON doesn't match schema
- `{:error, {:cast_failed, reason}}` when cast/1 returns error
"""
@spec validate_response(Response.t(), map(), module() | map()) ::
        {:ok, Response.t()} | {:error, term()}
def validate_response(%Response{content: content} = response, atom_schema, schema_input) do
  with {:ok, data} <- decode_json(content),
       :ok <- Validator.validate(data, atom_schema),
       {:ok, casted} <- maybe_cast(data, schema_input) do
    {:ok, %{response | parsed: casted}}
  end
end

defp decode_json(content) do
  case Jason.decode(content) do
    {:ok, data} when is_map(data) -> {:ok, data}
    {:ok, _} -> {:error, {:invalid_json, content}}
    {:error, _} -> {:error, {:invalid_json, content}}
  end
end

defp maybe_cast(data, schema_input) when is_atom(schema_input) do
  if function_exported?(schema_input, :cast, 1) do
    case schema_input.cast(data) do
      {:ok, _} = ok -> ok
      {:error, reason} -> {:error, {:cast_failed, reason}}
    end
  else
    {:ok, data}
  end
end

defp maybe_cast(data, _map), do: {:ok, data}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/phoenix_ai/schema_validate_response_test.exs --trace`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_ai/schema.ex test/phoenix_ai/schema_validate_response_test.exs
git commit -m "feat(05): add Schema.validate_response/3 shared helper"
```

---

### Task 5: OpenAI adapter — inject response_format

**Files:**
- Modify: `lib/phoenix_ai/providers/openai.ex`
- Create: `test/phoenix_ai/providers/openai_structured_test.exs`

- [ ] **Step 1: Write failing test**

Create `test/phoenix_ai/providers/openai_structured_test.exs`:

```elixir
defmodule PhoenixAI.Providers.OpenAIStructuredTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Providers.OpenAI

  describe "chat/2 with schema_json" do
    test "injects response_format into request body" do
      schema_json = %{
        "type" => "object",
        "properties" => %{"name" => %{"type" => "string"}},
        "required" => ["name"]
      }

      # We test body construction by checking the request via Req mock
      # For unit test, verify format_body builds correct structure
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
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/phoenix_ai/providers/openai_structured_test.exs --trace`
Expected: FAIL — `build_body/3` not defined.

- [ ] **Step 3: Extract build_body and add response_format injection**

In `lib/phoenix_ai/providers/openai.ex`, extract the body construction into a public function (for testability) and add schema support:

```elixir
@doc false
@spec build_body(String.t(), [map()], keyword()) :: map()
def build_body(model, formatted_messages, opts) do
  %{
    "model" => model,
    "messages" => formatted_messages
  }
  |> maybe_put("tools", Keyword.get(opts, :tools_json))
  |> maybe_put("temperature", Keyword.get(opts, :temperature))
  |> maybe_put("max_tokens", Keyword.get(opts, :max_tokens))
  |> maybe_put_schema(Keyword.get(opts, :schema_json))
end

defp maybe_put_schema(body, nil), do: body

defp maybe_put_schema(body, schema_json) do
  Map.put(body, "response_format", %{
    "type" => "json_schema",
    "json_schema" => %{
      "name" => "structured_output",
      "strict" => true,
      "schema" => schema_json
    }
  })
end
```

Update `chat/2` to use `build_body`:

```elixir
def chat(messages, opts \\ []) do
  api_key = Keyword.fetch!(opts, :api_key)
  model = Keyword.get(opts, :model, "gpt-4o")
  base_url = Keyword.get(opts, :base_url, @default_base_url)
  provider_options = Keyword.get(opts, :provider_options, %{})

  body =
    build_body(model, format_messages(messages), opts)
    |> Map.merge(provider_options)

  # ... rest of HTTP call unchanged
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/phoenix_ai/providers/openai_structured_test.exs --trace`
Expected: PASS

- [ ] **Step 5: Run full test suite for regressions**

Run: `mix test`
Expected: All existing OpenAI tests still pass.

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_ai/providers/openai.ex test/phoenix_ai/providers/openai_structured_test.exs
git commit -m "feat(05): inject response_format in OpenAI adapter for structured output"
```

---

### Task 6: OpenRouter adapter — inject response_format (same as OpenAI)

**Files:**
- Modify: `lib/phoenix_ai/providers/openrouter.ex`
- Create: `test/phoenix_ai/providers/openrouter_structured_test.exs`

- [ ] **Step 1: Write failing test**

Create `test/phoenix_ai/providers/openrouter_structured_test.exs`:

```elixir
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/phoenix_ai/providers/openrouter_structured_test.exs --trace`
Expected: FAIL — `build_body/3` not defined.

- [ ] **Step 3: Extract build_body and add response_format injection**

Apply the same `build_body/3` + `maybe_put_schema/2` pattern to `lib/phoenix_ai/providers/openrouter.ex`:

```elixir
@doc false
@spec build_body(String.t(), [map()], keyword()) :: map()
def build_body(model, formatted_messages, opts) do
  %{
    "model" => model,
    "messages" => formatted_messages
  }
  |> maybe_put("tools", Keyword.get(opts, :tools_json))
  |> maybe_put("temperature", Keyword.get(opts, :temperature))
  |> maybe_put("max_tokens", Keyword.get(opts, :max_tokens))
  |> maybe_put_schema(Keyword.get(opts, :schema_json))
end

defp maybe_put_schema(body, nil), do: body

defp maybe_put_schema(body, schema_json) do
  Map.put(body, "response_format", %{
    "type" => "json_schema",
    "json_schema" => %{
      "name" => "structured_output",
      "strict" => true,
      "schema" => schema_json
    }
  })
end
```

Update `do_chat/2` to use `build_body`:

```elixir
defp do_chat(messages, opts) do
  api_key = Keyword.fetch!(opts, :api_key)
  model = Keyword.get(opts, :model)
  base_url = Keyword.get(opts, :base_url, @default_base_url)
  provider_options = Keyword.get(opts, :provider_options, %{})

  body =
    build_body(model, format_messages(messages), opts)
    |> Map.merge(Map.drop(provider_options, ["http_referer", "x_title"]))

  # ... rest unchanged
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/phoenix_ai/providers/openrouter_structured_test.exs --trace`
Expected: PASS

- [ ] **Step 5: Run full test suite**

Run: `mix test`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_ai/providers/openrouter.ex test/phoenix_ai/providers/openrouter_structured_test.exs
git commit -m "feat(05): inject response_format in OpenRouter adapter for structured output"
```

---

### Task 7: Anthropic adapter — synthetic tool injection + extraction

**Files:**
- Modify: `lib/phoenix_ai/providers/anthropic.ex`
- Create: `test/phoenix_ai/providers/anthropic_structured_test.exs`

- [ ] **Step 1: Write failing tests**

Create `test/phoenix_ai/providers/anthropic_structured_test.exs`:

```elixir
defmodule PhoenixAI.Providers.AnthropicStructuredTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Providers.Anthropic
  alias PhoenixAI.Response

  @schema_json %{
    "type" => "object",
    "properties" => %{"name" => %{"type" => "string"}},
    "required" => ["name"]
  }

  describe "build_body/4 with schema_json (no existing tools)" do
    test "injects synthetic tool and tool_choice any" do
      body = Anthropic.build_body("claude-sonnet-4-5", [], 4096, schema_json: @schema_json)

      assert [tool] = body["tools"]
      assert tool["name"] == "structured_output"
      assert tool["input_schema"] == @schema_json
      assert body["tool_choice"] == %{"type" => "any"}
    end
  end

  describe "build_body/4 with schema_json and existing tools_json" do
    test "appends synthetic tool to existing tools and uses tool_choice auto" do
      existing_tools = [%{"name" => "get_weather", "input_schema" => %{}}]

      body =
        Anthropic.build_body("claude-sonnet-4-5", [], 4096,
          schema_json: @schema_json,
          tools_json: existing_tools
        )

      assert length(body["tools"]) == 2
      tool_names = Enum.map(body["tools"], & &1["name"])
      assert "get_weather" in tool_names
      assert "structured_output" in tool_names
      assert body["tool_choice"] == %{"type" => "auto"}
    end
  end

  describe "build_body/4 without schema_json" do
    test "does not inject synthetic tool" do
      body = Anthropic.build_body("claude-sonnet-4-5", [], 4096, [])

      refute Map.has_key?(body, "tools")
      refute Map.has_key?(body, "tool_choice")
    end
  end

  describe "parse_response/1 with structured_output tool_use" do
    test "extracts tool_use input as JSON content and clears tool_calls" do
      body = %{
        "content" => [
          %{
            "type" => "tool_use",
            "id" => "toolu_01",
            "name" => "structured_output",
            "input" => %{"name" => "Alice"}
          }
        ],
        "stop_reason" => "tool_use",
        "model" => "claude-sonnet-4-5",
        "usage" => %{"input_tokens" => 10, "output_tokens" => 5}
      }

      response = Anthropic.parse_response(body)

      assert response.content == ~s({"name":"Alice"})
      assert response.tool_calls == []
    end

    test "does not interfere with real tool_use blocks" do
      body = %{
        "content" => [
          %{"type" => "tool_use", "id" => "toolu_01", "name" => "get_weather", "input" => %{"city" => "Lisbon"}}
        ],
        "stop_reason" => "tool_use",
        "model" => "claude-sonnet-4-5",
        "usage" => %{}
      }

      response = Anthropic.parse_response(body)

      assert length(response.tool_calls) == 1
      assert hd(response.tool_calls).name == "get_weather"
    end

    test "handles mixed real and synthetic tool_use blocks" do
      body = %{
        "content" => [
          %{"type" => "text", "text" => "Here's the data:"},
          %{"type" => "tool_use", "id" => "toolu_01", "name" => "structured_output", "input" => %{"result" => "ok"}}
        ],
        "stop_reason" => "tool_use",
        "model" => "claude-sonnet-4-5",
        "usage" => %{}
      }

      response = Anthropic.parse_response(body)

      # structured_output extracted as content, not as tool_call
      assert response.content == ~s({"result":"ok"})
      assert response.tool_calls == []
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/phoenix_ai/providers/anthropic_structured_test.exs --trace`
Expected: FAIL — `build_body/4` not defined.

- [ ] **Step 3: Implement build_body and parse_response changes**

In `lib/phoenix_ai/providers/anthropic.ex`:

**Add `build_body/4`:**

```elixir
@doc false
@spec build_body(String.t(), [map()], non_neg_integer(), keyword()) :: map()
def build_body(model, formatted_messages, max_tokens, opts) do
  schema_json = Keyword.get(opts, :schema_json)
  tools_json = Keyword.get(opts, :tools_json)

  %{
    "model" => model,
    "messages" => formatted_messages,
    "max_tokens" => max_tokens
  }
  |> maybe_put("temperature", Keyword.get(opts, :temperature))
  |> inject_schema_and_tools(schema_json, tools_json)
end

defp inject_schema_and_tools(body, nil, nil), do: body

defp inject_schema_and_tools(body, nil, tools_json) do
  Map.put(body, "tools", tools_json)
end

defp inject_schema_and_tools(body, schema_json, nil) do
  synthetic = %{
    "name" => "structured_output",
    "description" => "Return structured response matching the schema",
    "input_schema" => schema_json
  }

  body
  |> Map.put("tools", [synthetic])
  |> Map.put("tool_choice", %{"type" => "any"})
end

defp inject_schema_and_tools(body, schema_json, tools_json) do
  synthetic = %{
    "name" => "structured_output",
    "description" => "Return structured response matching the schema",
    "input_schema" => schema_json
  }

  body
  |> Map.put("tools", tools_json ++ [synthetic])
  |> Map.put("tool_choice", %{"type" => "auto"})
end
```

**Update `chat/2` to use `build_body/4`:**

```elixir
def chat(messages, opts \\ []) do
  api_key = Keyword.fetch!(opts, :api_key)
  model = Keyword.get(opts, :model, "claude-sonnet-4-5")
  base_url = Keyword.get(opts, :base_url, @default_base_url)
  provider_options = Keyword.get(opts, :provider_options, %{})
  api_version = Map.get(provider_options, "anthropic-version", @default_api_version)
  max_tokens = Keyword.get(opts, :max_tokens, 4096)

  system = extract_system(messages)

  body =
    build_body(model, format_messages(messages), max_tokens, opts)
    |> maybe_put("system", system)
    |> Map.merge(Map.drop(provider_options, ["anthropic-version"]))

  # ... rest of HTTP call unchanged
end
```

**Update `parse_response/1` to detect structured_output:**

```elixir
def parse_response(body) do
  content_blocks = Map.get(body, "content", [])
  stop_reason = Map.get(body, "stop_reason")
  model = Map.get(body, "model")
  usage = Map.get(body, "usage", %{})

  {structured_input, remaining_blocks} = extract_structured_output(content_blocks)

  text_content = extract_text_content(remaining_blocks)
  tool_calls = extract_tool_calls(remaining_blocks)

  # If structured output was found, use its JSON as content
  final_content =
    if structured_input do
      Jason.encode!(structured_input)
    else
      text_content
    end

  %Response{
    content: final_content,
    finish_reason: stop_reason,
    model: model,
    usage: usage,
    tool_calls: tool_calls,
    provider_response: body
  }
end

defp extract_structured_output(content_blocks) do
  case Enum.split_with(content_blocks, fn
    %{"type" => "tool_use", "name" => "structured_output"} -> true
    _ -> false
  end) do
    {[%{"input" => input} | _], remaining} -> {input, remaining}
    {[], blocks} -> {nil, blocks}
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/phoenix_ai/providers/anthropic_structured_test.exs --trace`
Expected: PASS

- [ ] **Step 5: Run full test suite**

Run: `mix test`
Expected: All existing Anthropic tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_ai/providers/anthropic.ex test/phoenix_ai/providers/anthropic_structured_test.exs
git commit -m "feat(05): add synthetic tool injection and extraction in Anthropic adapter"
```

---

### Task 8: AI.chat/2 — schema-aware dispatch with validation

**Files:**
- Modify: `lib/ai.ex`
- Create: `test/phoenix_ai/ai_structured_test.exs`

- [ ] **Step 1: Write failing tests**

Create `test/phoenix_ai/ai_structured_test.exs`:

```elixir
defmodule AIStructuredTest do
  use ExUnit.Case, async: false

  import Mox

  alias PhoenixAI.{Message, Response, Schema}

  setup :verify_on_exit!

  @schema %{
    type: :object,
    properties: %{
      name: %{type: :string},
      age: %{type: :integer}
    },
    required: [:name, :age]
  }

  describe "chat/2 with schema option" do
    test "resolves schema, passes schema_json to provider, validates and populates parsed" do
      expect(PhoenixAI.MockProvider, :chat, fn _messages, opts ->
        # Verify schema_json was passed
        assert opts[:schema_json] == %{
                 "type" => "object",
                 "properties" => %{
                   "name" => %{"type" => "string"},
                   "age" => %{"type" => "integer"}
                 },
                 "required" => ["name", "age"]
               }

        {:ok, %Response{content: ~s({"name":"Alice","age":30}), tool_calls: []}}
      end)

      result =
        AI.chat(
          [%Message{role: :user, content: "Who?"}],
          provider: PhoenixAI.MockProvider,
          api_key: "test-key",
          schema: @schema
        )

      assert {:ok, %Response{parsed: %{"name" => "Alice", "age" => 30}}} = result
    end

    test "returns invalid_json when provider returns non-JSON content" do
      expect(PhoenixAI.MockProvider, :chat, fn _messages, _opts ->
        {:ok, %Response{content: "Not JSON at all", tool_calls: []}}
      end)

      result =
        AI.chat(
          [%Message{role: :user, content: "Who?"}],
          provider: PhoenixAI.MockProvider,
          api_key: "test-key",
          schema: @schema
        )

      assert {:error, {:invalid_json, "Not JSON at all"}} = result
    end

    test "returns validation_failed when JSON doesn't match schema" do
      expect(PhoenixAI.MockProvider, :chat, fn _messages, _opts ->
        {:ok, %Response{content: ~s({"name":"Alice"}), tool_calls: []}}
      end)

      result =
        AI.chat(
          [%Message{role: :user, content: "Who?"}],
          provider: PhoenixAI.MockProvider,
          api_key: "test-key",
          schema: @schema
        )

      assert {:error, {:validation_failed, details}} = result
      assert "age" in details.missing_keys
    end

    test "without schema option, does not validate or set parsed" do
      expect(PhoenixAI.MockProvider, :chat, fn _messages, opts ->
        refute Keyword.has_key?(opts, :schema_json)
        {:ok, %Response{content: "Hello!", tool_calls: []}}
      end)

      result =
        AI.chat(
          [%Message{role: :user, content: "Hi"}],
          provider: PhoenixAI.MockProvider,
          api_key: "test-key"
        )

      assert {:ok, %Response{content: "Hello!", parsed: nil}} = result
    end

    test "schema works with tools (ToolLoop path)" do
      PhoenixAI.MockProvider
      |> expect(:format_tools, fn tools ->
        assert [PhoenixAI.TestTools.WeatherTool] = tools
        [%{"type" => "function", "function" => %{"name" => "get_weather"}}]
      end)
      |> expect(:chat, fn _messages, opts ->
        assert opts[:schema_json] != nil
        assert opts[:tools_json] != nil
        {:ok, %Response{content: ~s({"name":"Weather","age":1}), tool_calls: []}}
      end)

      result =
        AI.chat(
          [%Message{role: :user, content: "Weather?"}],
          provider: PhoenixAI.MockProvider,
          api_key: "test-key",
          tools: [PhoenixAI.TestTools.WeatherTool],
          schema: @schema
        )

      assert {:ok, %Response{parsed: %{"name" => "Weather", "age" => 1}}} = result
    end

    test "schema works with behaviour module" do
      expect(PhoenixAI.MockProvider, :chat, fn _messages, opts ->
        assert opts[:schema_json]["required"] == ["sentiment", "confidence"]
        {:ok, %Response{content: ~s({"sentiment":"positive","confidence":0.95}), tool_calls: []}}
      end)

      result =
        AI.chat(
          [%Message{role: :user, content: "Analyze"}],
          provider: PhoenixAI.MockProvider,
          api_key: "test-key",
          schema: PhoenixAI.TestSchemas.SentimentSchema
        )

      assert {:ok, %Response{parsed: %{"sentiment" => "positive", "confidence" => 0.95}}} = result
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/phoenix_ai/ai_structured_test.exs --trace`
Expected: FAIL — AI.chat doesn't handle `:schema` option.

- [ ] **Step 3: Implement schema-aware dispatch in AI.chat/2**

Modify `lib/ai.ex`:

```elixir
defmodule AI do
  alias PhoenixAI.{Config, Schema}

  @known_providers [:openai, :anthropic, :openrouter]

  @spec chat([PhoenixAI.Message.t()], keyword()) ::
          {:ok, PhoenixAI.Response.t()} | {:error, term()}
  def chat(messages, opts \\ []) do
    provider_atom = opts[:provider] || default_provider()

    case resolve_provider(provider_atom) do
      {:ok, provider_mod} ->
        merged_opts = Config.resolve(provider_atom, Keyword.delete(opts, :provider))
        dispatch(provider_mod, messages, merged_opts, provider_atom)

      {:error, _} = error ->
        error
    end
  end

  defp dispatch(provider_mod, messages, opts, provider_atom) do
    case Keyword.get(opts, :api_key) do
      nil -> {:error, {:missing_api_key, provider_atom}}
      _key -> run_with_schema(provider_mod, messages, opts)
    end
  end

  defp run_with_schema(provider_mod, messages, opts) do
    schema_input = Keyword.get(opts, :schema)

    if schema_input do
      schema_json = Schema.resolve(schema_input)
      atom_schema = Schema.schema_map(schema_input)

      provider_opts =
        opts
        |> Keyword.drop([:schema])
        |> Keyword.put(:schema_json, schema_json)

      case run_with_tools(provider_mod, messages, provider_opts) do
        {:ok, response} ->
          Schema.validate_response(response, atom_schema, schema_input)

        error ->
          error
      end
    else
      run_with_tools(provider_mod, messages, Keyword.drop(opts, [:schema]))
    end
  end

  defp run_with_tools(provider_mod, messages, opts) do
    tools = Keyword.get(opts, :tools)

    if tools && tools != [] do
      PhoenixAI.ToolLoop.run(provider_mod, messages, tools, opts)
    else
      provider_mod.chat(messages, opts)
    end
  end

  # ... rest unchanged (provider_module, resolve_provider, default_provider)
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/phoenix_ai/ai_structured_test.exs --trace`
Expected: PASS

- [ ] **Step 5: Run full test suite**

Run: `mix test`
Expected: All tests pass, including existing AI tests.

- [ ] **Step 6: Commit**

```bash
git add lib/ai.ex test/phoenix_ai/ai_structured_test.exs
git commit -m "feat(05): add schema-aware dispatch with validation in AI.chat/2"
```

---

### Task 9: Agent — accept :schema and validate responses

**Files:**
- Modify: `lib/phoenix_ai/agent.ex`
- Create: `test/phoenix_ai/agent_structured_test.exs`

- [ ] **Step 1: Write failing tests**

Create `test/phoenix_ai/agent_structured_test.exs`:

```elixir
defmodule PhoenixAI.AgentStructuredTest do
  use ExUnit.Case, async: false

  import Mox

  alias PhoenixAI.{Agent, Message, Response, Schema}

  @schema %{
    type: :object,
    properties: %{
      name: %{type: :string},
      age: %{type: :integer}
    },
    required: [:name, :age]
  }

  setup do
    Mox.set_mode({:global, self()})
    :ok
  end

  describe "prompt/2 with schema" do
    test "validates response and populates parsed" do
      expect(PhoenixAI.MockProvider, :chat, fn _messages, opts ->
        assert opts[:schema_json] != nil
        {:ok, %Response{content: ~s({"name":"Alice","age":30}), tool_calls: []}}
      end)

      {:ok, pid} =
        Agent.start_link(
          provider: PhoenixAI.MockProvider,
          api_key: "test-key",
          schema: @schema
        )

      assert {:ok, %Response{parsed: %{"name" => "Alice", "age" => 30}}} =
               Agent.prompt(pid, "Who?")
    end

    test "returns validation_failed for bad JSON shape" do
      expect(PhoenixAI.MockProvider, :chat, fn _messages, _opts ->
        {:ok, %Response{content: ~s({"name":"Alice"}), tool_calls: []}}
      end)

      {:ok, pid} =
        Agent.start_link(
          provider: PhoenixAI.MockProvider,
          api_key: "test-key",
          schema: @schema
        )

      assert {:error, {:validation_failed, details}} = Agent.prompt(pid, "Who?")
      assert "age" in details.missing_keys
    end

    test "returns invalid_json for non-JSON response" do
      expect(PhoenixAI.MockProvider, :chat, fn _messages, _opts ->
        {:ok, %Response{content: "Not JSON", tool_calls: []}}
      end)

      {:ok, pid} =
        Agent.start_link(
          provider: PhoenixAI.MockProvider,
          api_key: "test-key",
          schema: @schema
        )

      assert {:error, {:invalid_json, "Not JSON"}} = Agent.prompt(pid, "Who?")
    end

    test "without schema, parsed is nil" do
      expect(PhoenixAI.MockProvider, :chat, fn _messages, _opts ->
        {:ok, %Response{content: "Hello!", tool_calls: []}}
      end)

      {:ok, pid} =
        Agent.start_link(
          provider: PhoenixAI.MockProvider,
          api_key: "test-key"
        )

      assert {:ok, %Response{content: "Hello!", parsed: nil}} = Agent.prompt(pid, "Hi")
    end

    test "schema works with behaviour module" do
      expect(PhoenixAI.MockProvider, :chat, fn _messages, opts ->
        assert opts[:schema_json]["required"] == ["sentiment", "confidence"]
        {:ok, %Response{content: ~s({"sentiment":"positive","confidence":0.9}), tool_calls: []}}
      end)

      {:ok, pid} =
        Agent.start_link(
          provider: PhoenixAI.MockProvider,
          api_key: "test-key",
          schema: PhoenixAI.TestSchemas.SentimentSchema
        )

      assert {:ok, %Response{parsed: %{"sentiment" => "positive", "confidence" => 0.9}}} =
               Agent.prompt(pid, "Analyze")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/phoenix_ai/agent_structured_test.exs --trace`
Expected: FAIL — Agent doesn't handle `:schema`.

- [ ] **Step 3: Add schema support to Agent**

Modify `lib/phoenix_ai/agent.ex`:

1. Add `:schema` to the struct:

```elixir
defstruct [
  :provider_mod,
  :provider_atom,
  :system,
  :manage_history,
  :pending,
  :pending_user_msg,
  :schema,
  tools: [],
  messages: [],
  opts: []
]
```

2. In `init/1`, extract schema and prepare schema_json:

```elixir
def init(opts) do
  Process.flag(:trap_exit, true)

  provider_atom = Keyword.fetch!(opts, :provider)
  provider_mod = AI.provider_module(provider_atom)
  system = Keyword.get(opts, :system)
  tools = Keyword.get(opts, :tools, [])
  manage_history = Keyword.get(opts, :manage_history, true)
  schema = Keyword.get(opts, :schema)

  provider_opts =
    opts
    |> Keyword.drop([:provider, :system, :tools, :manage_history, :name, :schema])
    |> then(&Config.resolve(provider_atom, &1))

  # If schema provided, resolve and add schema_json to opts
  provider_opts =
    if schema do
      schema_json = PhoenixAI.Schema.resolve(schema)
      Keyword.put(provider_opts, :schema_json, schema_json)
    else
      provider_opts
    end

  state = %__MODULE__{
    provider_mod: provider_mod,
    provider_atom: provider_atom,
    system: system,
    tools: tools,
    manage_history: manage_history,
    schema: schema,
    opts: provider_opts
  }

  {:ok, state}
end
```

3. In `handle_info` (Task result), add validation:

```elixir
def handle_info({ref, result}, %{pending: {from, ref}} = state) do
  Process.demonitor(ref, [:flush])

  # Validate against schema if present
  result = maybe_validate_schema(result, state.schema)

  new_messages =
    case {state.manage_history, result} do
      {true, {:ok, %Response{} = response}} ->
        assistant_msg = %Message{
          role: :assistant,
          content: response.content,
          tool_calls: response.tool_calls
        }

        state.messages ++ [state.pending_user_msg, assistant_msg]

      _ ->
        state.messages
    end

  GenServer.reply(from, result)
  {:noreply, %{state | pending: nil, pending_user_msg: nil, messages: new_messages}}
end

defp maybe_validate_schema({:ok, %Response{} = response}, schema) when not is_nil(schema) do
  atom_schema = PhoenixAI.Schema.schema_map(schema)
  PhoenixAI.Schema.validate_response(response, atom_schema, schema)
end

defp maybe_validate_schema(result, _schema), do: result
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/phoenix_ai/agent_structured_test.exs --trace`
Expected: PASS

- [ ] **Step 5: Run full test suite**

Run: `mix test`
Expected: All tests pass, including existing Agent tests.

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_ai/agent.ex test/phoenix_ai/agent_structured_test.exs
git commit -m "feat(05): add schema support to Agent GenServer"
```

---

### Task 10: Quality checks and final verification

**Files:**
- No new files

- [ ] **Step 1: Run full test suite**

Run: `mix test --trace`
Expected: All tests pass.

- [ ] **Step 2: Run formatter**

Run: `mix format --check-formatted`
Expected: No formatting issues.

- [ ] **Step 3: Run Credo**

Run: `mix credo`
Expected: No issues.

- [ ] **Step 4: Run Dialyzer (if configured)**

Run: `mix dialyzer`
Expected: No errors (warnings are OK for first run).

- [ ] **Step 5: Verify SCHEMA requirements coverage**

Manually verify against requirements:
- **SCHEMA-01**: Schema defined as plain map — ✓ Task 2 (`Schema.resolve/1` with maps)
- **SCHEMA-02**: Provider adapters translate schema — ✓ Tasks 5, 6, 7 (OpenAI, OpenRouter, Anthropic)
- **SCHEMA-03**: Response validation casts JSON — ✓ Task 4 (`validate_response/3`)
- **SCHEMA-04**: Validation failure returns error with details — ✓ Task 3 (`Validator`) + Task 4 (error propagation)

- [ ] **Step 6: Commit any formatting fixes**

```bash
mix format
git add -A
git commit -m "style(05): format structured output code"
```

(Skip if no changes.)

---

*Plan: 05-structured-output*
*Created: 2026-03-30*
