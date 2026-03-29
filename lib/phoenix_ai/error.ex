defmodule PhoenixAI.Error do
  @moduledoc "Represents an error returned from an AI provider or internal operation."

  @type t :: %__MODULE__{
          status: integer() | nil,
          message: String.t() | nil,
          provider: atom() | nil
        }

  defstruct [:status, :message, :provider]
end
