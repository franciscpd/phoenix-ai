defmodule PhoenixAI.Team do
  @moduledoc """
  Parallel fan-out/fan-in execution.

  Agent specs run concurrently via `Task.async_stream`. Results are collected
  and passed to a merge function. Crashed specs produce `{:error, {:task_failed, reason}}`
  instead of crashing the caller.

  ## Ad-hoc usage

      Team.run([
        fn -> AI.chat([msg("Search X")], provider: :openai) end,
        fn -> AI.chat([msg("Search Y")], provider: :anthropic) end
      ], fn results -> merge(results) end, max_concurrency: 5)

  ## DSL usage

      defmodule MyTeam do
        use PhoenixAI.Team

        agent :researcher do
          fn -> AI.chat([msg("Search")], provider: :openai) end
        end

        merge do
          fn results -> Enum.map(results, fn {:ok, r} -> r.content end) end
        end
      end

      MyTeam.run()
  """

  @type agent_spec :: (-> {:ok, term()} | {:error, term()} | term())
  @type merge_fn :: ([{:ok, term()} | {:error, term()}] -> term())

  @default_max_concurrency 5

  @doc """
  Executes agent specs in parallel and merges results.

  Each spec is a zero-arity function. Results are collected in input order
  and passed to `merge_fn`. Crashed specs produce `{:error, {:task_failed, reason}}`.

  ## Options

  - `:max_concurrency` — maximum parallel tasks (default: 5)
  - `:timeout` — per-task timeout in ms (default: `:infinity`)
  - `:ordered` — preserve input order in results (default: `true`)
  """
  @spec run([agent_spec()], merge_fn(), keyword()) :: {:ok, term()}
  def run(specs, merge_fn, opts \\ []) do
    max_concurrency = Keyword.get(opts, :max_concurrency, @default_max_concurrency)
    timeout = Keyword.get(opts, :timeout, :infinity)
    ordered = Keyword.get(opts, :ordered, true)

    results =
      specs
      |> Task.async_stream(fn spec -> safe_execute(spec) end,
        max_concurrency: max_concurrency,
        timeout: timeout,
        on_timeout: :kill_task,
        ordered: ordered
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, reason} -> {:error, {:task_failed, reason}}
      end)

    {:ok, merge_fn.(results)}
  end

  defp safe_execute(spec) do
    spec.()
  rescue
    e -> {:error, {:task_failed, Exception.message(e)}}
  end
end
