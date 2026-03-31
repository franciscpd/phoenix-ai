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
