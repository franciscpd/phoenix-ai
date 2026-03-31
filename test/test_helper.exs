Mox.defmock(PhoenixAI.MockProvider, for: PhoenixAI.Provider)

{:ok, _} = Registry.start_link(keys: :unique, name: PhoenixAI.TestRegistry)

ExUnit.start()
