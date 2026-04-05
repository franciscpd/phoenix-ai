defmodule PhoenixAI.Providers.TestProvider do
  @moduledoc """
  Test provider for offline testing. Returns scripted responses without network calls.

  Supports two modes:
  - **Queue (FIFO):** Pre-defined responses consumed in order
  - **Handler:** Custom function receives messages and opts

  State is per-process (keyed by PID) for async test isolation.
  """

  @behaviour PhoenixAI.Provider

  alias PhoenixAI.{Response, StreamChunk}

  # --- State Management ---

  def start_state(pid) do
    name = via(pid)

    case Agent.start_link(fn -> %{responses: [], handler: nil, calls: []} end, name: name) do
      {:ok, agent_pid} -> {:ok, agent_pid}
      {:error, {:already_started, agent_pid}} -> {:ok, agent_pid}
    end
  end

  def stop_state(pid) do
    case GenServer.whereis(via(pid)) do
      nil ->
        :ok

      agent_pid ->
        try do
          Agent.stop(agent_pid)
        catch
          :exit, _ -> :ok
        end
    end
  end

  def put_responses(pid, responses) when is_list(responses) do
    Agent.update(via(pid), fn state ->
      %{state | responses: state.responses ++ responses}
    end)
  end

  def put_handler(pid, handler) when is_function(handler, 2) do
    Agent.update(via(pid), fn state ->
      %{state | handler: handler}
    end)
  end

  def get_calls(pid) do
    Agent.get(via(pid), fn state -> Enum.reverse(state.calls) end)
  end

  defp via(pid), do: {:via, Registry, {PhoenixAI.TestRegistry, pid}}

  defp get_state(pid) do
    case GenServer.whereis(via(pid)) do
      nil -> nil
      _agent -> Agent.get(via(pid), & &1)
    end
  end

  defp record_call(pid, messages, opts) do
    Agent.update(via(pid), fn state ->
      %{state | calls: [{messages, opts} | state.calls]}
    end)
  end

  # --- Provider Behaviour ---

  @impl PhoenixAI.Provider
  def chat(messages, opts) do
    caller = self()

    case get_state(caller) do
      nil ->
        {:error, :test_provider_not_configured}

      %{handler: handler} when is_function(handler, 2) ->
        record_call(caller, messages, opts)
        handler.(messages, opts)

      %{responses: []} ->
        {:error, :no_more_responses}

      %{responses: [response | _rest]} ->
        record_call(caller, messages, opts)

        Agent.update(via(caller), fn state ->
          %{state | responses: tl(state.responses)}
        end)

        response
    end
  end

  @impl PhoenixAI.Provider
  def parse_response(body), do: %{body | provider: :test}

  @impl PhoenixAI.Provider
  def format_tools(tools), do: Enum.map(tools, fn mod -> %{"name" => mod.name()} end)

  @impl PhoenixAI.Provider
  def stream(messages, callback, opts) do
    case chat(messages, opts) do
      {:ok, %Response{content: content} = response} ->
        content
        |> String.graphemes()
        |> Enum.each(fn char ->
          callback.(%StreamChunk{delta: char})
        end)

        callback.(%StreamChunk{finish_reason: "stop", usage: response.usage})
        {:ok, response}

      error ->
        error
    end
  end

  @impl PhoenixAI.Provider
  def parse_chunk(%{data: data}), do: %StreamChunk{delta: data}
end
