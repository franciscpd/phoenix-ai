defmodule PhoenixAI.Config do
  @moduledoc "Resolves configuration with cascade: call-site > config.exs > env vars > defaults."

  @env_vars %{
    openai: "OPENAI_API_KEY",
    anthropic: "ANTHROPIC_API_KEY",
    openrouter: "OPENROUTER_API_KEY"
  }

  @default_models %{
    openai: "gpt-4o",
    anthropic: "claude-sonnet-4-5"
  }

  @spec resolve(atom(), keyword()) :: keyword()
  def resolve(provider, call_site_opts) do
    app_config = Application.get_env(:phoenix_ai, provider, [])
    env_opts = env_opts(provider)
    defaults = default_opts(provider)

    defaults
    |> Keyword.merge(env_opts)
    |> Keyword.merge(app_config)
    |> Keyword.merge(call_site_opts)
  end

  defp env_opts(provider) do
    case Map.get(@env_vars, provider) do
      nil ->
        []

      env_var ->
        case System.get_env(env_var) do
          nil -> []
          key -> [api_key: key]
        end
    end
  end

  defp default_opts(provider) do
    case Map.get(@default_models, provider) do
      nil -> []
      model -> [model: model]
    end
  end
end
