defmodule PhoenixAI.Usage do
  @moduledoc """
  Normalized token usage from any AI provider.

  All provider-specific usage data is mapped to a consistent shape
  via `from_provider/2`. The original raw data is preserved in
  `provider_specific` for backward compatibility.

  ## Examples

      iex> PhoenixAI.Usage.from_provider(:openai, %{"prompt_tokens" => 10, "completion_tokens" => 20, "total_tokens" => 30})
      %PhoenixAI.Usage{input_tokens: 10, output_tokens: 20, total_tokens: 30, provider_specific: %{"prompt_tokens" => 10, "completion_tokens" => 20, "total_tokens" => 30}}

  """

  @type t :: %__MODULE__{
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer(),
          total_tokens: non_neg_integer(),
          cache_read_tokens: non_neg_integer() | nil,
          cache_creation_tokens: non_neg_integer() | nil,
          provider_specific: map()
        }

  defstruct input_tokens: 0,
            output_tokens: 0,
            total_tokens: 0,
            cache_read_tokens: nil,
            cache_creation_tokens: nil,
            provider_specific: %{}

  @doc """
  Maps raw provider usage data to a normalized `%Usage{}` struct.

  Accepts a provider atom and the raw usage map from the provider's
  JSON response. Returns a `%Usage{}` with consistent field names.

  ## Supported providers

    * `:openai` — maps `prompt_tokens`, `completion_tokens`, `total_tokens`
    * `:anthropic` — maps `input_tokens`, `output_tokens`, cache fields; auto-calculates `total_tokens`
    * `:openrouter` — delegates to `:openai` (same wire format)
    * Any other atom — generic fallback that tries both naming conventions

  When `raw` is `nil` or an empty map, returns a zero-valued `%Usage{}`.
  """
  @spec from_provider(atom(), map() | nil) :: t()
  def from_provider(:openai, raw) when is_map(raw) do
    input = Map.get(raw, "prompt_tokens", 0)
    output = Map.get(raw, "completion_tokens", 0)
    total = Map.get(raw, "total_tokens", 0)

    %__MODULE__{
      input_tokens: input,
      output_tokens: output,
      total_tokens: if(total == 0, do: input + output, else: total),
      provider_specific: raw
    }
  end
end
