defmodule PhoenixAI.Guardrails.Policies.ToolPolicy do
  @moduledoc """
  Policy that enforces tool allowlists or denylists.

  Inspects `request.tool_calls` and halts on the first tool that violates
  the configured list. Cannot set both `:allow` and `:deny`.

  ## Options

    * `:allow` — list of permitted tool names (allowlist mode)
    * `:deny` — list of blocked tool names (denylist mode)

  ## Example

      policies = [
        {ToolPolicy, [allow: ["search", "calculate"]]}
      ]

      Pipeline.run(policies, request)
  """

  @behaviour PhoenixAI.Guardrails.Policy

  alias PhoenixAI.Guardrails.{PolicyViolation, Request}

  @impl true
  def check(%Request{} = request, opts) do
    allow = Keyword.get(opts, :allow)
    deny = Keyword.get(opts, :deny)

    validate_opts!(allow, deny)

    case request.tool_calls do
      nil -> {:ok, request}
      [] -> {:ok, request}
      tool_calls -> check_tools(tool_calls, allow, deny, request)
    end
  end

  defp validate_opts!(allow, deny) when not is_nil(allow) and not is_nil(deny) do
    raise ArgumentError, "ToolPolicy: cannot set both :allow and :deny"
  end

  defp validate_opts!(_allow, _deny), do: :ok

  defp check_tools(tool_calls, allow, nil, request) when is_list(allow) do
    case Enum.find(tool_calls, fn tc -> not is_binary(tc.name) or tc.name not in allow end) do
      nil -> {:ok, request}
      tc -> halt_violation(tc.name || "<unnamed>", :allow)
    end
  end

  defp check_tools(tool_calls, nil, deny, request) when is_list(deny) do
    case Enum.find(tool_calls, fn tc -> is_binary(tc.name) and tc.name in deny end) do
      nil -> {:ok, request}
      tc -> halt_violation(tc.name, :deny)
    end
  end

  defp check_tools(_tool_calls, nil, nil, request), do: {:ok, request}

  defp halt_violation(tool_name, mode) do
    message =
      case mode do
        :allow -> "not in allowlist"
        :deny -> "is in denylist"
      end

    {:halt,
     %PolicyViolation{
       policy: __MODULE__,
       reason: "Tool '#{tool_name}' #{message}",
       metadata: %{tool: tool_name, mode: mode}
     }}
  end
end
