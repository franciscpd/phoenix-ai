defmodule PhoenixAI.Guardrails.Policies.ContentFilter do
  @moduledoc """
  Policy that applies user-provided function hooks for content inspection.

  Hooks receive the full `Request` and can modify it or reject with an error.
  The `:pre` hook runs first, then `:post`. If `:pre` rejects, `:post` never runs.

  ## Options

    * `:pre` — `fn(Request.t()) -> {:ok, Request.t()} | {:error, String.t()}`
    * `:post` — `fn(Request.t()) -> {:ok, Request.t()} | {:error, String.t()}`

  ## Example

      pre_hook = fn request ->
        sanitized = sanitize_messages(request.messages)
        {:ok, %{request | messages: sanitized}}
      end

      policies = [{ContentFilter, [pre: pre_hook]}]
      Pipeline.run(policies, request)
  """

  @behaviour PhoenixAI.Guardrails.Policy

  alias PhoenixAI.Guardrails.{PolicyViolation, Request}

  @impl true
  def check(%Request{} = request, opts) do
    pre = Keyword.get(opts, :pre)
    post = Keyword.get(opts, :post)

    with {:ok, request} <- apply_hook(pre, request),
         {:ok, request} <- apply_hook(post, request) do
      {:ok, request}
    else
      {:error, reason} ->
        {:halt, %PolicyViolation{policy: __MODULE__, reason: reason}}

      other ->
        {:halt,
         %PolicyViolation{
           policy: __MODULE__,
           reason: "ContentFilter: hook returned unexpected value: #{inspect(other)}"
         }}
    end
  end

  defp apply_hook(nil, request), do: {:ok, request}
  defp apply_hook(hook, request) when is_function(hook, 1), do: hook.(request)

  defp apply_hook(hook, _request) do
    {:error, "ContentFilter: hook must be a 1-arity function, got: #{inspect(hook)}"}
  end
end
