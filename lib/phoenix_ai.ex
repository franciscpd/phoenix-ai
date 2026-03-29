defmodule PhoenixAI do
  @moduledoc """
  PhoenixAI — AI integration library for Elixir.

  ## Supervision

  Add `PhoenixAI.child_spec()` to your application's supervision tree:

      def start(_type, _args) do
        children = [
          PhoenixAI.child_spec(),
          # ... your other children
        ]
        Supervisor.start_link(children, strategy: :one_for_one)
      end

  This starts a Finch HTTP pool used for streaming in later phases.
  The library never auto-starts processes.
  """

  @doc """
  Returns a child spec for the PhoenixAI supervision subtree.

  ## Options

  - `:finch_name` — Name for the Finch pool (default: `PhoenixAI.Finch`)
  """
  def child_spec(opts \\ []) do
    finch_name = Keyword.get(opts, :finch_name, PhoenixAI.Finch)

    children = [
      {Finch, name: finch_name}
    ]

    %{
      id: __MODULE__,
      start: {Supervisor, :start_link, [children, [strategy: :one_for_one]]},
      type: :supervisor
    }
  end
end
