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

  defmacro __using__(_opts) do
    quote do
      import PhoenixAI.Team, only: [agent: 2, merge: 1]
      Module.register_attribute(__MODULE__, :team_agents, accumulate: true)
      Module.register_attribute(__MODULE__, :team_merge_fn, accumulate: false)
      @before_compile PhoenixAI.Team
    end
  end

  @doc """
  Defines a named agent spec in a team module.

  The block must return a zero-arity function `fn -> {:ok, result} | {:error, reason} end`.
  """
  defmacro agent(name, do: block) do
    escaped_block = Macro.escape(block)

    quote do
      @team_agents {unquote(name), unquote(escaped_block)}
    end
  end

  @doc """
  Defines the merge function for a team module.

  The block must return a function that accepts a list of result tuples.
  """
  defmacro merge(do: block) do
    escaped_block = Macro.escape(block)

    quote do
      @team_merge_fn unquote(escaped_block)
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    agents = Module.get_attribute(env.module, :team_agents) |> Enum.reverse()
    merge_fn_ast = Module.get_attribute(env.module, :team_merge_fn)

    agent_funs_ast = Enum.map(agents, fn {_name, fun_ast} -> fun_ast end)
    agent_names = Enum.map(agents, fn {name, _fun_ast} -> name end)

    quote do
      @doc "Returns the list of agent spec functions in definition order."
      def agents, do: unquote(agent_funs_ast)

      @doc "Returns the list of agent name atoms in definition order."
      def agent_names, do: unquote(agent_names)

      @doc "Returns the merge function."
      def merge_fn, do: unquote(merge_fn_ast)

      @doc "Runs the team with the given options."
      def run(opts \\ []) do
        PhoenixAI.Team.run(agents(), merge_fn(), opts)
      end
    end
  end

  @run_schema NimbleOptions.new!(
               max_concurrency: [
                 type: :pos_integer,
                 default: 5,
                 doc: "Max parallel tasks"
               ],
               timeout: [
                 type: {:custom, __MODULE__, :validate_timeout, []},
                 default: :infinity,
                 doc: "Per-task timeout in ms (:infinity or positive integer)"
               ],
               ordered: [type: :boolean, default: true, doc: "Preserve input order in results"]
             )

  @doc false
  def validate_timeout(:infinity), do: {:ok, :infinity}
  def validate_timeout(val) when is_integer(val) and val > 0, do: {:ok, val}

  def validate_timeout(val),
    do: {:error, "expected :infinity or positive integer, got: #{inspect(val)}"}

  @doc """
  Executes agent specs in parallel and merges results.

  Each spec is a zero-arity function. Results are collected in input order
  and passed to `merge_fn`. Crashed specs produce `{:error, {:task_failed, reason}}`.

  ## Options

  - `:max_concurrency` — maximum parallel tasks (default: 5)
  - `:timeout` — per-task timeout in ms (default: `:infinity`)
  - `:ordered` — preserve input order in results (default: `true`)
  """
  @spec run([agent_spec()], merge_fn(), keyword()) :: {:ok, term()} | {:error, term()}
  def run(specs, merge_fn, opts \\ []) do
    case NimbleOptions.validate(opts, @run_schema) do
      {:ok, validated_opts} -> do_run(specs, merge_fn, validated_opts)
      {:error, _} = error -> error
    end
  end

  defp do_run(specs, merge_fn, opts) do
    max_concurrency = Keyword.get(opts, :max_concurrency, @default_max_concurrency)
    timeout = Keyword.get(opts, :timeout, :infinity)
    ordered = Keyword.get(opts, :ordered, true)
    start_time = System.monotonic_time()

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

    duration = System.monotonic_time() - start_time
    success_count = Enum.count(results, &match?({:ok, _}, &1))
    error_count = length(results) - success_count

    :telemetry.execute(
      [:phoenix_ai, :team, :complete],
      %{duration: duration},
      %{agent_count: length(specs), success_count: success_count, error_count: error_count}
    )

    {:ok, merge_fn.(results)}
  end

  defp safe_execute(spec) do
    spec.()
  rescue
    e -> {:error, {:task_failed, Exception.message(e)}}
  end
end
