Mox.defmock(PhoenixAI.MockProvider, for: PhoenixAI.Provider)
Mox.defmock(PhoenixAI.Guardrails.MockPolicy, for: PhoenixAI.Guardrails.Policy)
Mox.defmock(PhoenixAI.Guardrails.MockDetector, for: PhoenixAI.Guardrails.JailbreakDetector)

{:ok, _} = Registry.start_link(keys: :unique, name: PhoenixAI.TestRegistry)

ExUnit.start()
