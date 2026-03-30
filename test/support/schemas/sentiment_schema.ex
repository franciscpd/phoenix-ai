defmodule PhoenixAI.TestSchemas.SentimentSchema do
  @moduledoc false
  @behaviour PhoenixAI.Schema

  @impl true
  def schema do
    %{
      type: :object,
      properties: %{
        sentiment: %{type: :string, enum: [:positive, :negative, :neutral]},
        confidence: %{type: :number}
      },
      required: [:sentiment, :confidence]
    }
  end
end
