Mox.defmock(PhoenixAI.MockProvider, for: PhoenixAI.Provider)
Mox.defmock(PhoenixAI.Guardrails.MockPolicy, for: PhoenixAI.Guardrails.Policy)

{:ok, _} = Registry.start_link(keys: :unique, name: PhoenixAI.TestRegistry)

ExUnit.start()
