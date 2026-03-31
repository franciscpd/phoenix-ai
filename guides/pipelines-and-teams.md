# Pipelines & Teams

## Pipelines

`PhoenixAI.Pipeline` executes steps sequentially. Each step receives the previous
step's result. The pipeline halts on the first `{:error, reason}`.

This is the "railway-oriented programming" pattern: as long as each step returns
`{:ok, value}`, the value passes to the next step. An error stops the chain.

### Ad-hoc Pipeline

For one-off sequences, pass a list of functions to `Pipeline.run/3`:

```elixir
alias PhoenixAI.{Message, Response, Pipeline}

steps = [
  fn query ->
    messages = [%Message{role: :user, content: "Search for: #{query}"}]
    AI.chat(messages, provider: :openai)
  end,
  fn %Response{content: text} ->
    messages = [%Message{role: :user, content: "Summarize: #{text}"}]
    AI.chat(messages, provider: :openai)
  end,
  fn %Response{content: summary} ->
    String.upcase(summary)
  end
]

{:ok, result} = Pipeline.run(steps, "Elixir language features")
```

Each step can return:
- `{:ok, value}` — continue to next step with `value`
- `{:error, reason}` — halt the pipeline
- `any_other_value` — auto-wrapped as `{:ok, any_other_value}` and passed forward

### DSL Pipeline

For reusable pipelines, define a module with `use PhoenixAI.Pipeline`:

```elixir
defmodule MyApp.ResearchPipeline do
  use PhoenixAI.Pipeline

  step :search do
    fn query ->
      messages = [%PhoenixAI.Message{role: :user, content: "Research: #{query}"}]
      AI.chat(messages, provider: :openai, model: "gpt-4o")
    end
  end

  step :extract_facts do
    fn %PhoenixAI.Response{content: text} ->
      messages = [
        %PhoenixAI.Message{role: :system, content: "Extract key facts as bullet points."},
        %PhoenixAI.Message{role: :user, content: text}
      ]
      AI.chat(messages, provider: :openai)
    end
  end

  step :format do
    fn %PhoenixAI.Response{content: facts} ->
      "## Research Results\n\n#{facts}"
    end
  end
end

{:ok, result} = MyApp.ResearchPipeline.run("quantum computing breakthroughs 2024")
```

The generated `run/1` function is equivalent to:
```elixir
Pipeline.run(MyApp.ResearchPipeline.steps(), input, opts)
```

You can also inspect the pipeline structure:
```elixir
MyApp.ResearchPipeline.step_names()  # => [:search, :extract_facts, :format]
MyApp.ResearchPipeline.steps()       # => [fn, fn, fn]
```

### Error Handling in Pipelines

The pipeline halts on the first error:

```elixir
steps = [
  fn input ->
    case lookup_data(input) do
      {:ok, data} -> {:ok, data}
      {:error, :not_found} -> {:error, :search_failed}
    end
  end,
  fn data ->
    # This step is skipped if the previous one errored
    AI.chat([%Message{role: :user, content: "Analyze: #{data}"}], provider: :openai)
  end
]

case Pipeline.run(steps, "query") do
  {:ok, result} -> IO.puts(result)
  {:error, :search_failed} -> IO.puts("Nothing found")
  {:error, reason} -> IO.inspect(reason)
end
```

## Teams

`PhoenixAI.Team` runs multiple agent specs in parallel (fan-out) and merges results
(fan-in). Useful for calling multiple models or running independent research tasks
concurrently.

### Ad-hoc Team

```elixir
alias PhoenixAI.{Message, Team}

specs = [
  fn ->
    AI.chat(
      [%Message{role: :user, content: "Analyze from a technical perspective: Elixir"}],
      provider: :openai
    )
  end,
  fn ->
    AI.chat(
      [%Message{role: :user, content: "Analyze from a business perspective: Elixir"}],
      provider: :anthropic
    )
  end
]

merge_fn = fn results ->
  contents = Enum.map(results, fn
    {:ok, response} -> response.content
    {:error, _} -> "(agent failed)"
  end)
  Enum.join(contents, "\n\n---\n\n")
end

{:ok, combined} = Team.run(specs, merge_fn, max_concurrency: 2, timeout: 30_000)
```

### DSL Team

```elixir
defmodule MyApp.ResearchTeam do
  use PhoenixAI.Team

  agent :technical do
    fn ->
      AI.chat(
        [%PhoenixAI.Message{role: :user, content: "Technical analysis of Elixir"}],
        provider: :openai,
        model: "gpt-4o"
      )
    end
  end

  agent :business do
    fn ->
      AI.chat(
        [%PhoenixAI.Message{role: :user, content: "Business case for Elixir"}],
        provider: :anthropic
      )
    end
  end

  merge do
    fn results ->
      results
      |> Enum.map(fn
        {:ok, response} -> response.content
        {:error, reason} -> "Error: #{inspect(reason)}"
      end)
      |> Enum.join("\n\n---\n\n")
    end
  end
end

{:ok, report} = MyApp.ResearchTeam.run()
{:ok, report} = MyApp.ResearchTeam.run(max_concurrency: 3, timeout: 60_000)
```

### Team Options

| Option | Default | Description |
|---|---|---|
| `:max_concurrency` | `5` | Maximum parallel tasks |
| `:timeout` | `:infinity` | Per-task timeout in milliseconds |
| `:ordered` | `true` | Preserve input order in results |

### Fault Isolation

If an agent spec crashes, the error is isolated and appears as `{:error, {:task_failed, reason}}`
in the results — the other agents and the merge function are not affected:

```elixir
merge do
  fn results ->
    {successes, failures} = Enum.split_with(results, &match?({:ok, _}, &1))

    if failures != [] do
      IO.warn("#{length(failures)} agent(s) failed")
    end

    successes
    |> Enum.map(fn {:ok, r} -> r.content end)
    |> Enum.join("\n\n")
  end
end
```

## Composition

### Pipeline Calling a Team

```elixir
defmodule MyApp.ResearchPipeline do
  use PhoenixAI.Pipeline

  step :gather do
    fn topic ->
      # Run a team in parallel, get combined results
      MyApp.ResearchTeam.run()
    end
  end

  step :summarize do
    fn combined_text ->
      AI.chat(
        [%PhoenixAI.Message{role: :user, content: "Final summary:\n#{combined_text}"}],
        provider: :openai
      )
    end
  end
end
```

### Team Using a Pipeline

```elixir
defmodule MyApp.DeepDiveTeam do
  use PhoenixAI.Team

  agent :english_pipeline do
    fn ->
      MyApp.TranslatePipeline.run("Hello world")
    end
  end

  agent :french_pipeline do
    fn ->
      MyApp.TranslatePipeline.run("Bonjour le monde")
    end
  end

  merge do
    fn results ->
      {:ok, Enum.map(results, fn {:ok, r} -> r end)}
    end
  end
end
```

### Ad-hoc Composition

```elixir
# Pipeline step that fans out to a team
steps = [
  fn query -> {:ok, query} end,
  fn query ->
    Team.run(
      [
        fn -> AI.chat([%Message{role: :user, content: "Pros of #{query}"}], provider: :openai) end,
        fn -> AI.chat([%Message{role: :user, content: "Cons of #{query}"}], provider: :openai) end
      ],
      fn results ->
        Enum.map(results, fn {:ok, r} -> r.content end)
      end
    )
  end,
  fn [pros, cons] ->
    AI.chat(
      [%Message{role: :user, content: "Pros: #{pros}\n\nCons: #{cons}\n\nFinal verdict?"}],
      provider: :openai
    )
  end
]

{:ok, verdict} = Pipeline.run(steps, "using microservices")
```
