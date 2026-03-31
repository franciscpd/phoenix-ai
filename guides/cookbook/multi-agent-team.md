# Cookbook: Multi-Agent Team

This recipe demonstrates parallel research using `PhoenixAI.Team`, where a technical
agent and a business agent run concurrently and their results are merged.

## Pattern Overview

```
                 ┌─ Technical Agent (OpenAI) ─┐
User Request ───┤                              ├─→ merge/1 → Combined Report
                 └─ Business Agent (Anthropic) ┘
```

## DSL Implementation

```elixir
defmodule MyApp.ResearchTeam do
  use PhoenixAI.Team

  alias PhoenixAI.Message

  agent :technical do
    fn ->
      messages = [
        %Message{
          role: :system,
          content: "You are a senior software engineer. Provide a technical analysis."
        },
        %Message{
          role: :user,
          content: "Analyze the technical aspects of adopting Elixir for a fintech startup."
        }
      ]

      AI.chat(messages, provider: :openai, model: "gpt-4o")
    end
  end

  agent :business do
    fn ->
      messages = [
        %Message{
          role: :system,
          content: "You are a business analyst. Provide a business perspective."
        },
        %Message{
          role: :user,
          content: "Analyze the business case for adopting Elixir for a fintech startup."
        }
      ]

      AI.chat(messages, provider: :anthropic, model: "claude-sonnet-4-5")
    end
  end

  merge do
    fn results ->
      sections =
        Enum.zip([:technical, :business], results)
        |> Enum.map(fn {name, result} ->
          content =
            case result do
              {:ok, response} -> response.content
              {:error, reason} -> "Analysis unavailable: #{inspect(reason)}"
            end

          "## #{String.capitalize(to_string(name))} Analysis\n\n#{content}"
        end)

      Enum.join(sections, "\n\n---\n\n")
    end
  end
end
```

## Usage

```elixir
{:ok, report} = MyApp.ResearchTeam.run()
IO.puts(report)

# With options
{:ok, report} = MyApp.ResearchTeam.run(
  max_concurrency: 2,
  timeout: 60_000
)
```

## Dynamic Team (Ad-hoc)

When the agents or topics are determined at runtime:

```elixir
defmodule MyApp.DynamicResearch do
  alias PhoenixAI.{Message, Team}

  def research(topic, perspectives) do
    specs =
      Enum.map(perspectives, fn perspective ->
        fn ->
          messages = [
            %Message{
              role: :system,
              content: "Provide a #{perspective} perspective."
            },
            %Message{
              role: :user,
              content: "Analyze: #{topic}"
            }
          ]

          AI.chat(messages, provider: :openai)
        end
      end)

    merge_fn = fn results ->
      results
      |> Enum.zip(perspectives)
      |> Enum.map(fn {result, perspective} ->
        content =
          case result do
            {:ok, r} -> r.content
            {:error, _} -> "(failed)"
          end

        "### #{perspective}\n#{content}"
      end)
      |> Enum.join("\n\n")
    end

    Team.run(specs, merge_fn, max_concurrency: length(perspectives))
  end
end

# Usage
{:ok, report} = MyApp.DynamicResearch.research(
  "Elixir for fintech",
  ["technical", "business", "security", "regulatory"]
)
```

## Handling Partial Failures

The merge function always receives all results. Handle failures gracefully:

```elixir
merge do
  fn results ->
    {successes, failures} = Enum.split_with(results, &match?({:ok, _}, &1))

    if failures != [] do
      # Log or alert on partial failures
      Enum.each(failures, fn {:error, reason} ->
        require Logger
        Logger.warning("Agent failed: #{inspect(reason)}")
      end)
    end

    case successes do
      [] ->
        {:error, :all_agents_failed}

      _ ->
        combined =
          successes
          |> Enum.map(fn {:ok, r} -> r.content end)
          |> Enum.join("\n\n---\n\n")

        {:ok, combined}
    end
  end
end
```

Note: The merge function's return is wrapped in `{:ok, merge_result}` by `Team.run/3`.
If you need to propagate errors, wrap your entire `run/1` call and inspect the merge output.

## Testing

```elixir
defmodule MyApp.ResearchTeamTest do
  use ExUnit.Case, async: true
  use PhoenixAI.Test

  alias PhoenixAI.Response

  test "runs both agents and merges results" do
    set_responses([
      {:ok, %Response{content: "Technical: Elixir is great for concurrency"}},
      {:ok, %Response{content: "Business: Elixir reduces operational costs"}}
    ])

    {:ok, report} = MyApp.ResearchTeam.run()

    assert report =~ "Technical Analysis"
    assert report =~ "Business Analysis"
    assert report =~ "concurrency"
    assert report =~ "operational costs"
  end

  test "handles agent failure gracefully" do
    set_responses([
      {:ok, %Response{content: "Technical analysis here"}},
      {:error, :rate_limited}
    ])

    {:ok, report} = MyApp.ResearchTeam.run()

    assert report =~ "Technical Analysis"
    assert report =~ "Analysis unavailable"
  end
end
```
