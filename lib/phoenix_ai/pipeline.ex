defmodule PhoenixAI.Pipeline do
  @moduledoc """
  Sequential railway pipeline.

  Steps execute in order. Each step receives the previous step's unwrapped
  `{:ok, value}` result. The pipeline halts on the first `{:error, reason}`.

  ## Ad-hoc usage

      Pipeline.run([
        fn query -> AI.chat([msg(query)], provider: :openai) end,
        fn %Response{content: text} -> String.upcase(text) end
      ], "Hello")

  ## DSL usage

      defmodule MyPipeline do
        use PhoenixAI.Pipeline

        step :search do
          fn query -> AI.chat([msg(query)], provider: :openai) end
        end
      end

      MyPipeline.run("Hello")
  """

  @type step :: (term() -> {:ok, term()} | {:error, term()} | term())

  defmacro __using__(_opts) do
    quote do
      import PhoenixAI.Pipeline, only: [step: 2]
      Module.register_attribute(__MODULE__, :pipeline_steps, accumulate: true)
      @before_compile PhoenixAI.Pipeline
    end
  end

  @doc """
  Defines a named step in a pipeline module.

  The block must return a function `fn input -> {:ok, result} | {:error, reason} | term() end`.
  """
  defmacro step(name, do: block) do
    # Store the block as escaped AST so __before_compile__ can splice it back in.
    escaped_block = Macro.escape(block)

    quote do
      @pipeline_steps {unquote(name), unquote(escaped_block)}
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    steps = Module.get_attribute(env.module, :pipeline_steps) |> Enum.reverse()
    # Each fun_ast is already quoted AST (stored via Macro.escape); unquote it
    # inside a list literal so it becomes valid AST for the function body.
    step_funs_ast = Enum.map(steps, fn {_name, fun_ast} -> fun_ast end)
    step_names = Enum.map(steps, fn {name, _fun_ast} -> name end)

    quote do
      @doc "Returns the list of step functions in definition order."
      def steps, do: unquote(step_funs_ast)

      @doc "Returns the list of step name atoms in definition order."
      def step_names, do: unquote(step_names)

      @doc "Runs the pipeline with the given input."
      def run(input, opts \\ []) do
        PhoenixAI.Pipeline.run(steps(), input, opts)
      end
    end
  end

  @doc """
  Executes a list of step functions sequentially.

  Each step receives the unwrapped value from the previous step's `{:ok, value}`.
  Halts on first `{:error, reason}`. Raw (non-tuple) returns are auto-wrapped
  in `{:ok, value}`.
  """
  @spec run([step()], term(), keyword()) :: {:ok, term()} | {:error, term()}
  def run(steps, input, opts \\ [])

  def run([], input, _opts), do: {:ok, input}

  def run(steps, input, _opts) do
    # Accumulator is always {:ok, value}; {:error, _} is only produced via :halt.
    Enum.reduce_while(steps, {:ok, input}, fn step, {:ok, value} ->
      case normalize_return(step.(value)) do
        {:ok, _} = ok -> {:cont, ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  @doc false
  defp normalize_return({:ok, _} = ok), do: ok
  defp normalize_return({:error, _} = err), do: err
  defp normalize_return(other), do: {:ok, other}
end
