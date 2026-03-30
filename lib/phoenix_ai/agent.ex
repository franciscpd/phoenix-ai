defmodule PhoenixAI.Agent do
  @moduledoc """
  Stateful GenServer that owns one conversation and runs the completion-tool-call loop.

  ## Modes

  - **`manage_history: true`** (default) — Agent accumulates messages between `prompt/2`
    calls. The conversation grows automatically, like Laravel/AI's Agent.
  - **`manage_history: false`** — Agent is a stateless runner. Consumer passes `messages:`
    in each `prompt/3` call and manages history externally.

  ## Usage

      {:ok, pid} = PhoenixAI.Agent.start_link(
        provider: :openai,
        model: "gpt-4o",
        system: "You are a helpful assistant.",
        tools: [MyApp.Weather],
        api_key: "sk-..."
      )

      {:ok, response} = PhoenixAI.Agent.prompt(pid, "What's the weather in Lisbon?")
      response.content
      #=> "The weather in Lisbon is sunny, 22°C!"

      {:ok, response} = PhoenixAI.Agent.prompt(pid, "And in Porto?")

  ## Supervision

  Start under a DynamicSupervisor:

      DynamicSupervisor.start_child(MyApp.AgentSupervisor, {PhoenixAI.Agent, opts})
  """

  use GenServer

  alias PhoenixAI.{Config, Message, Response, Schema, ToolLoop}

  @default_timeout 60_000

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

  # --- Public API ---

  @doc "Starts an Agent GenServer. See module docs for options."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, init_opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, init_opts, gen_opts)
  end

  @doc """
  Sends a prompt to the agent and waits for the response.

  Blocks until the provider (and any tool calls) complete.
  Default timeout: 60 seconds.

  ## Options (prompt/3)

  - `:messages` — override conversation history (for `manage_history: false`)
  - `:timeout` — override call timeout in milliseconds
  """
  @spec prompt(GenServer.server(), String.t(), keyword()) ::
          {:ok, Response.t()} | {:error, term()}
  def prompt(server, text, opts \\ []) do
    {timeout, msg_opts} = Keyword.pop(opts, :timeout, @default_timeout)
    GenServer.call(server, {:prompt, text, msg_opts}, timeout)
  end

  @doc "Returns the accumulated conversation messages."
  @spec get_messages(GenServer.server()) :: [Message.t()]
  def get_messages(server) do
    GenServer.call(server, :get_messages)
  end

  @doc "Clears conversation history, keeps configuration. Returns `{:error, :agent_busy}` if a prompt is in flight."
  @spec reset(GenServer.server()) :: :ok | {:error, :agent_busy}
  def reset(server) do
    GenServer.call(server, :reset)
  end

  # --- GenServer Callbacks ---

  @impl GenServer
  def init(opts) do
    # Trap exits so Task.async crashes become messages instead of killing the Agent
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

    provider_opts =
      if schema do
        schema_json = Schema.resolve(schema)
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

  @impl GenServer
  def handle_call({:prompt, _text, _msg_opts}, _from, %{pending: {_, _}} = state) do
    {:reply, {:error, :agent_busy}, state}
  end

  def handle_call({:prompt, text, msg_opts}, from, state) do
    user_msg = %Message{role: :user, content: text}
    messages = build_messages(state, user_msg, msg_opts)

    task =
      Task.async(fn ->
        if state.tools != [] do
          ToolLoop.run(state.provider_mod, messages, state.tools, state.opts)
        else
          state.provider_mod.chat(messages, state.opts)
        end
      end)

    {:noreply, %{state | pending: {from, task.ref}, pending_user_msg: user_msg}}
  end

  def handle_call(:get_messages, _from, state) do
    {:reply, state.messages, state}
  end

  def handle_call(:reset, _from, %{pending: {_, _}} = state) do
    {:reply, {:error, :agent_busy}, state}
  end

  def handle_call(:reset, _from, state) do
    {:reply, :ok, %{state | messages: []}}
  end

  @impl GenServer
  def handle_info({ref, result}, %{pending: {from, ref}} = state) do
    Process.demonitor(ref, [:flush])

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

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{pending: {from, ref}} = state) do
    GenServer.reply(from, {:error, {:agent_task_failed, reason}})
    {:noreply, %{state | pending: nil, pending_user_msg: nil}}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # --- Private Helpers ---

  defp maybe_validate_schema({:ok, %Response{} = response}, schema) when not is_nil(schema) do
    atom_schema = Schema.schema_map(schema)
    Schema.validate_response(response, atom_schema, schema)
  end

  defp maybe_validate_schema(result, _schema), do: result

  defp build_messages(state, user_msg, msg_opts) do
    system_msgs =
      if state.system do
        [%Message{role: :system, content: state.system}]
      else
        []
      end

    history =
      if state.manage_history do
        state.messages
      else
        Keyword.get(msg_opts, :messages, [])
      end

    system_msgs ++ history ++ [user_msg]
  end
end
