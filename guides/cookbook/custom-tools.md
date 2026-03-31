# Cookbook: Custom Tools

Tools allow AI models to call your Elixir functions. This recipe shows how to build
and test tool modules.

## Basic Calculator Tool

A simple arithmetic tool with no external dependencies:

```elixir
defmodule MyApp.CalculatorTool do
  @behaviour PhoenixAI.Tool

  @impl true
  def name, do: "calculate"

  @impl true
  def description, do: "Performs basic arithmetic operations"

  @impl true
  def parameters_schema do
    %{
      type: :object,
      properties: %{
        operation: %{
          type: :string,
          enum: ["add", "subtract", "multiply", "divide"],
          description: "The arithmetic operation to perform"
        },
        a: %{type: :number, description: "First operand"},
        b: %{type: :number, description: "Second operand"}
      },
      required: [:operation, :a, :b]
    }
  end

  @impl true
  def execute(%{"operation" => "add", "a" => a, "b" => b}, _opts) do
    {:ok, "#{a + b}"}
  end

  def execute(%{"operation" => "subtract", "a" => a, "b" => b}, _opts) do
    {:ok, "#{a - b}"}
  end

  def execute(%{"operation" => "multiply", "a" => a, "b" => b}, _opts) do
    {:ok, "#{a * b}"}
  end

  def execute(%{"operation" => "divide", "a" => _a, "b" => 0}, _opts) do
    {:error, "Division by zero"}
  end

  def execute(%{"operation" => "divide", "a" => a, "b" => b}, _opts) do
    {:ok, "#{a / b}"}
  end
end
```

Usage:

```elixir
{:ok, response} = AI.chat(
  [%PhoenixAI.Message{role: :user, content: "What is 42 * 7?"}],
  provider: :openai,
  tools: [MyApp.CalculatorTool]
)

IO.puts(response.content)
# => "42 multiplied by 7 equals 294."
```

## Tool with External API (GitHub Search)

A tool that calls an external API and handles errors:

```elixir
defmodule MyApp.GitHubSearchTool do
  @behaviour PhoenixAI.Tool

  @impl true
  def name, do: "github_search"

  @impl true
  def description, do: "Search GitHub repositories by keyword"

  @impl true
  def parameters_schema do
    %{
      type: :object,
      properties: %{
        query: %{
          type: :string,
          description: "Search keywords"
        },
        language: %{
          type: :string,
          description: "Filter by programming language (optional)"
        },
        limit: %{
          type: :integer,
          description: "Number of results (1-10, default 5)"
        }
      },
      required: [:query]
    }
  end

  @impl true
  def execute(args, _opts) do
    query = args["query"]
    language = args["language"]
    limit = min(args["limit"] || 5, 10)

    q =
      if language do
        "#{query} language:#{language}"
      else
        query
      end

    url = "https://api.github.com/search/repositories"

    case Req.get(url,
           params: [q: q, per_page: limit, sort: "stars"],
           headers: [{"accept", "application/vnd.github+json"}]
         ) do
      {:ok, %{status: 200, body: %{"items" => items}}} ->
        results =
          Enum.map(items, fn repo ->
            "#{repo["full_name"]} (⭐ #{repo["stargazers_count"]}): #{repo["description"]}"
          end)
          |> Enum.join("\n")

        {:ok, results}

      {:ok, %{status: 403}} ->
        {:error, "GitHub API rate limit exceeded"}

      {:ok, %{status: status}} ->
        {:error, "GitHub API returned status #{status}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end
end
```

Usage:

```elixir
{:ok, response} = AI.chat(
  [%PhoenixAI.Message{role: :user, content: "Find popular Elixir web frameworks on GitHub"}],
  provider: :openai,
  tools: [MyApp.GitHubSearchTool]
)
```

## Multi-Tool Agent

Combine multiple tools in an agent:

```elixir
{:ok, agent} = PhoenixAI.Agent.start_link(
  provider: :openai,
  model: "gpt-4o",
  system: "You are a research assistant with access to calculations and GitHub search.",
  tools: [MyApp.CalculatorTool, MyApp.GitHubSearchTool]
)

{:ok, r1} = PhoenixAI.Agent.prompt(agent, "Search for Elixir HTTP client libraries")
{:ok, r2} = PhoenixAI.Agent.prompt(agent, "How many total stars do the top 3 have?")
# Agent can call CalculatorTool to add up the stars
```

## Testing Tools with TestProvider

Use `PhoenixAI.Test` to test your tool-using code without real API calls.

### Scripted Tool Call Response

Use `set_handler/1` to simulate a model that calls a tool:

```elixir
defmodule MyApp.CalculatorToolTest do
  use ExUnit.Case, async: true
  use PhoenixAI.Test

  alias PhoenixAI.{Message, Response, ToolCall}

  test "tool is called when model requests it" do
    # First response: model calls the tool
    # Second response: model uses the tool result
    set_handler(fn messages, _opts ->
      last = List.last(messages)

      cond do
        last.role == :user and last.content =~ "42 * 7" ->
          # Simulate model deciding to call the tool
          {:ok,
           %Response{
             content: nil,
             tool_calls: [
               %ToolCall{
                 id: "call_123",
                 name: "calculate",
                 arguments: %{"operation" => "multiply", "a" => 42, "b" => 7}
               }
             ]
           }}

        last.role == :tool ->
          # Model received tool result, now answers
          {:ok, %Response{content: "42 multiplied by 7 is 294."}}

        true ->
          {:ok, %Response{content: "I don't understand"}}
      end
    end)

    {:ok, response} = AI.chat(
      [%Message{role: :user, content: "What is 42 * 7?"}],
      provider: :test,
      api_key: "test",
      tools: [MyApp.CalculatorTool]
    )

    assert response.content == "42 multiplied by 7 is 294."
  end
end
```

### Testing Tool execute/2 Directly

Test the tool itself in isolation:

```elixir
defmodule MyApp.CalculatorToolUnitTest do
  use ExUnit.Case, async: true

  test "adds two numbers" do
    assert {:ok, "10"} =
             MyApp.CalculatorTool.execute(
               %{"operation" => "add", "a" => 7, "b" => 3},
               []
             )
  end

  test "rejects division by zero" do
    assert {:error, "Division by zero"} =
             MyApp.CalculatorTool.execute(
               %{"operation" => "divide", "a" => 5, "b" => 0},
               []
             )
  end

  test "multiplies correctly" do
    assert {:ok, "294"} =
             MyApp.CalculatorTool.execute(
               %{"operation" => "multiply", "a" => 42, "b" => 7},
               []
             )
  end
end
```

### Verifying Calls Were Made

```elixir
test "records tool-related calls" do
  set_responses([
    {:ok, %Response{content: "The answer is 42."}}
  ])

  AI.chat(
    [%Message{role: :user, content: "Answer?"}],
    provider: :test,
    api_key: "test",
    tools: [MyApp.CalculatorTool]
  )

  calls = get_calls()
  assert length(calls) == 1
end
```

## Best Practices

1. **Return strings from execute/2** — The model expects text. Format numbers, lists,
   and structs as human-readable strings.

2. **Handle all error cases** — Return `{:error, "message"}` rather than raising.
   The tool loop will include the error message in the conversation so the model
   can inform the user.

3. **Be specific in descriptions** — The model uses `description/0` and
   `parameters_schema/0` to decide when and how to call your tool. Clear descriptions
   lead to more accurate tool usage.

4. **Validate inputs** — Models can produce unexpected arguments. Pattern match
   defensively and return helpful error messages for invalid inputs.

5. **Keep tools focused** — One tool, one capability. Compose with multiple tools
   rather than building a single tool that does everything.
