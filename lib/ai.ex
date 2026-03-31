defmodule AI do
  @moduledoc """
  Thin facade for interacting with AI providers.

  ## Usage

      AI.chat(
        [%PhoenixAI.Message{role: :user, content: "Hello"}],
        provider: :openai,
        model: "gpt-4o"
      )

  ## Configuration Cascade

  Options resolve in order: call-site > config.exs > env vars > provider defaults.
  """

  alias PhoenixAI.{Config, Schema}

  @known_providers [:openai, :anthropic, :openrouter, :test]

  @common_opts [
    provider: [type: :atom, doc: "Provider identifier (:openai, :anthropic, :openrouter, :test)"],
    model: [type: :string, doc: "Model identifier"],
    api_key: [type: :string, doc: "API key — overrides config/env resolution"],
    temperature: [type: :float, doc: "Sampling temperature (0.0-2.0)"],
    max_tokens: [type: :pos_integer, doc: "Maximum tokens in response"],
    tools: [type: {:list, :atom}, default: [], doc: "Tool modules implementing PhoenixAI.Tool"],
    schema: [type: :any, doc: "JSON schema map for structured output validation"],
    provider_options: [
      type: {:map, :atom, :any},
      default: %{},
      doc: "Provider-specific passthrough"
    ]
  ]

  @chat_schema NimbleOptions.new!(@common_opts)

  @stream_schema NimbleOptions.new!(
                   @common_opts ++
                     [
                       on_chunk: [type: {:fun, 1}, doc: "Callback receiving %StreamChunk{} structs"],
                       to: [type: :pid, doc: "PID to receive {:phoenix_ai, {:chunk, chunk}} messages"]
                     ]
                 )

  @spec chat([PhoenixAI.Message.t()], keyword()) ::
          {:ok, PhoenixAI.Response.t()} | {:error, term()}
  def chat(messages, opts \\ []) do
    case NimbleOptions.validate(opts, @chat_schema) do
      {:ok, validated_opts} -> do_chat(messages, validated_opts)
      {:error, _} = error -> error
    end
  end

  defp do_chat(messages, opts) do
    provider_atom = opts[:provider] || default_provider()
    meta = %{provider: provider_atom, model: opts[:model]}

    :telemetry.span([:phoenix_ai, :chat], meta, fn ->
      result =
        case resolve_provider(provider_atom) do
          {:ok, provider_mod} ->
            merged_opts = Config.resolve(provider_atom, Keyword.delete(opts, :provider))
            dispatch(provider_mod, messages, merged_opts, provider_atom)

          {:error, _} = error ->
            error
        end

      stop_meta = Map.merge(meta, telemetry_stop_meta(result))
      {result, stop_meta}
    end)
  end

  @spec stream([PhoenixAI.Message.t()], keyword()) ::
          {:ok, PhoenixAI.Response.t()} | {:error, term()}
  def stream(messages, opts \\ []) do
    case NimbleOptions.validate(opts, @stream_schema) do
      {:ok, validated_opts} -> do_stream(messages, validated_opts)
      {:error, _} = error -> error
    end
  end

  defp do_stream(messages, opts) do
    provider_atom = opts[:provider] || default_provider()
    meta = %{provider: provider_atom, model: opts[:model]}

    :telemetry.span([:phoenix_ai, :stream], meta, fn ->
      result =
        case resolve_provider(provider_atom) do
          {:ok, provider_mod} ->
            merged_opts = Config.resolve(provider_atom, Keyword.delete(opts, :provider))
            dispatch_stream(provider_mod, messages, merged_opts, provider_atom)

          {:error, _} = error ->
            error
        end

      stop_meta = Map.merge(meta, telemetry_stop_meta(result))
      {result, stop_meta}
    end)
  end

  defp telemetry_stop_meta({:ok, %PhoenixAI.Response{usage: usage}}) do
    %{status: :ok, usage: usage || %{}}
  end

  defp telemetry_stop_meta({:error, _}) do
    %{status: :error}
  end

  @doc false
  def build_callback(opts) do
    cond do
      fun = Keyword.get(opts, :on_chunk) -> fun
      pid = Keyword.get(opts, :to) -> fn chunk -> send(pid, {:phoenix_ai, {:chunk, chunk}}) end
      true -> fn chunk -> send(self(), {:phoenix_ai, {:chunk, chunk}}) end
    end
  end

  defp dispatch_stream(provider_mod, messages, opts, provider_atom) do
    case Keyword.get(opts, :api_key) do
      nil ->
        {:error, {:missing_api_key, provider_atom}}

      _key ->
        callback = build_callback(opts)
        tools = Keyword.get(opts, :tools)
        stream_opts = Keyword.drop(opts, [:on_chunk, :to, :schema, :tools])

        cond do
          tools && tools != [] ->
            PhoenixAI.Stream.run_with_tools(provider_mod, messages, callback, tools, stream_opts)

          function_exported?(provider_mod, :stream, 3) ->
            provider_mod.stream(messages, callback, stream_opts)

          true ->
            PhoenixAI.Stream.run(provider_mod, messages, callback, stream_opts)
        end
    end
  end

  defp dispatch(provider_mod, messages, opts, provider_atom) do
    case Keyword.get(opts, :api_key) do
      nil -> {:error, {:missing_api_key, provider_atom}}
      _key -> run_with_schema(provider_mod, messages, opts)
    end
  end

  defp run_with_schema(provider_mod, messages, opts) do
    schema_input = Keyword.get(opts, :schema)

    if schema_input do
      schema_json = Schema.resolve(schema_input)
      atom_schema = Schema.schema_map(schema_input)

      provider_opts =
        opts
        |> Keyword.drop([:schema])
        |> Keyword.put(:schema_json, schema_json)

      case run_with_tools(provider_mod, messages, provider_opts) do
        {:ok, response} ->
          Schema.validate_response(response, atom_schema, schema_input)

        error ->
          error
      end
    else
      run_with_tools(provider_mod, messages, Keyword.drop(opts, [:schema]))
    end
  end

  defp run_with_tools(provider_mod, messages, opts) do
    tools = Keyword.get(opts, :tools)

    if tools && tools != [] do
      PhoenixAI.ToolLoop.run(provider_mod, messages, tools, opts)
    else
      provider_mod.chat(messages, opts)
    end
  end

  @spec provider_module(atom()) :: module()
  def provider_module(:openai), do: PhoenixAI.Providers.OpenAI
  def provider_module(:anthropic), do: PhoenixAI.Providers.Anthropic
  def provider_module(:openrouter), do: PhoenixAI.Providers.OpenRouter
  def provider_module(:test), do: PhoenixAI.Providers.TestProvider
  def provider_module(mod) when is_atom(mod), do: mod

  defp resolve_provider(provider) when provider in @known_providers do
    mod = provider_module(provider)

    if Code.ensure_loaded?(mod) do
      {:ok, mod}
    else
      {:error, {:provider_not_implemented, provider}}
    end
  end

  defp resolve_provider(mod) when is_atom(mod) do
    if Code.ensure_loaded?(mod) and function_exported?(mod, :chat, 2) do
      {:ok, mod}
    else
      {:error, {:unknown_provider, mod}}
    end
  end

  defp default_provider do
    Application.get_env(:phoenix_ai, :default_provider, :openai)
  end
end
