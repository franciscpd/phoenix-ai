defmodule PhoenixAI.Guardrails.JailbreakDetector do
  @moduledoc """
  Behaviour for jailbreak detection implementations.

  Implementations analyze message content and return a detection
  result indicating whether jailbreak patterns were found.

  ## Example

      defmodule MyDetector do
        @behaviour PhoenixAI.Guardrails.JailbreakDetector

        @impl true
        def detect(content, _opts) do
          if suspicious?(content) do
            {:detected, %DetectionResult{score: 0.9, patterns: ["custom"]}}
          else
            {:safe, %DetectionResult{}}
          end
        end
      end
  """

  defmodule DetectionResult do
    @moduledoc "Result from a jailbreak detection scan."

    @type t :: %__MODULE__{
            score: float(),
            patterns: [String.t()],
            details: map()
          }

    defstruct score: 0.0, patterns: [], details: %{}
  end

  @callback detect(content :: String.t(), opts :: keyword()) ::
              {:safe, DetectionResult.t()} | {:detected, DetectionResult.t()}
end
