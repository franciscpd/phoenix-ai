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

  alias PhoenixAI.Config

  @known_providers [:openai, :anthropic, :openrouter]

  @spec chat([PhoenixAI.Message.t()], keyword()) ::
          {:ok, PhoenixAI.Response.t()} | {:error, term()}
  def chat(messages, opts \\ []) do
    provider_atom = opts[:provider] || default_provider()

    case resolve_provider(provider_atom) do
      {:ok, provider_mod} ->
        merged_opts = Config.resolve(provider_atom, Keyword.delete(opts, :provider))

        case merged_opts[:api_key] do
          nil -> {:error, {:missing_api_key, provider_atom}}
          _key -> provider_mod.chat(messages, merged_opts)
        end

      {:error, _} = error ->
        error
    end
  end

  @spec provider_module(atom()) :: module()
  def provider_module(:openai), do: PhoenixAI.Providers.OpenAI
  def provider_module(:anthropic), do: PhoenixAI.Providers.Anthropic
  def provider_module(:openrouter), do: PhoenixAI.Providers.OpenRouter
  def provider_module(mod) when is_atom(mod), do: mod

  defp resolve_provider(provider) when provider in @known_providers do
    {:ok, provider_module(provider)}
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
