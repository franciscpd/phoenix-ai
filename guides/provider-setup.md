# Provider Setup

PhoenixAI supports OpenAI, Anthropic, OpenRouter, and a built-in TestProvider for testing.

## Configuration Cascade

Options resolve in this order, from highest to lowest priority:

```
call-site opts  >  config.exs  >  env vars  >  provider defaults
```

This means you can set a default model in config, override it per call, and keep API keys
in environment variables without ever hardcoding them.

**Example:** If `OPENAI_API_KEY` is set in the environment and you call:

```elixir
AI.chat(messages, provider: :openai, model: "gpt-4o-mini")
```

The resolved opts will be: `[api_key: "sk-...", model: "gpt-4o-mini"]` — the env var
provides the key, the call-site provides the model.

## OpenAI

### Environment Variable

```bash
export OPENAI_API_KEY="sk-..."
```

### Application Config

```elixir
config :phoenix_ai, :openai,
  api_key: System.get_env("OPENAI_API_KEY"),
  model: "gpt-4o",
  temperature: 0.7,
  max_tokens: 2048
```

### Usage

```elixir
{:ok, response} = AI.chat(messages, provider: :openai)

# Override model at call site
{:ok, response} = AI.chat(messages, provider: :openai, model: "gpt-4o-mini")
```

Default model: `"gpt-4o"`

## Anthropic

### Environment Variable

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
```

### Application Config

```elixir
config :phoenix_ai, :anthropic,
  api_key: System.get_env("ANTHROPIC_API_KEY"),
  model: "claude-sonnet-4-5"
```

### Usage

```elixir
{:ok, response} = AI.chat(messages, provider: :anthropic)

# Use Claude Opus for complex tasks
{:ok, response} = AI.chat(messages, provider: :anthropic, model: "claude-opus-4-5")
```

Default model: `"claude-sonnet-4-5"`

## OpenRouter

OpenRouter provides access to many models (including OpenAI and Anthropic) through
a single API key. Useful for model routing and fallbacks.

### Environment Variable

```bash
export OPENROUTER_API_KEY="sk-or-..."
```

### Application Config

```elixir
config :phoenix_ai, :openrouter,
  api_key: System.get_env("OPENROUTER_API_KEY"),
  model: "openai/gpt-4o"
```

### Usage

```elixir
# Use any model available on OpenRouter
{:ok, response} = AI.chat(messages,
  provider: :openrouter,
  model: "anthropic/claude-sonnet-4-5"
)

{:ok, response} = AI.chat(messages,
  provider: :openrouter,
  model: "meta-llama/llama-3.1-70b-instruct"
)
```

## provider_options: Passthrough

Some provider-specific parameters are not part of PhoenixAI's standard schema.
Use `provider_options:` to pass arbitrary key-value pairs directly to the provider API:

```elixir
{:ok, response} = AI.chat(messages,
  provider: :openai,
  provider_options: %{
    seed: 42,
    logprobs: true
  }
)
```

```elixir
{:ok, response} = AI.chat(messages,
  provider: :anthropic,
  provider_options: %{
    top_k: 5
  }
)
```

The values in `provider_options` are merged into the request body before sending.

## TestProvider

`PhoenixAI.Providers.TestProvider` is a fully-featured in-process provider
that never makes HTTP requests. Use it in tests for fast, deterministic AI calls.

### Setup

```elixir
defmodule MyApp.SomeTest do
  use ExUnit.Case, async: true
  use PhoenixAI.Test   # sets up TestProvider per test, cleans up on_exit

  alias PhoenixAI.{Message, Response}

  test "my feature uses AI" do
    # Script responses in order
    set_responses([
      {:ok, %Response{content: "First response"}},
      {:ok, %Response{content: "Second response"}}
    ])

    {:ok, r1} = AI.chat([%Message{role: :user, content: "Q1"}],
      provider: :test, api_key: "test")
    {:ok, r2} = AI.chat([%Message{role: :user, content: "Q2"}],
      provider: :test, api_key: "test")

    assert r1.content == "First response"
    assert r2.content == "Second response"
  end
end
```

### Handler Mode

For dynamic responses based on input, use `set_handler/1`:

```elixir
set_handler(fn messages, _opts ->
  last = List.last(messages)
  {:ok, %Response{content: "You said: #{last.content}"}}
end)
```

### Inspecting Calls

```elixir
test "records all calls" do
  set_responses([{:ok, %Response{content: "ok"}}])

  AI.chat([%Message{role: :user, content: "hello"}],
    provider: :test, api_key: "test")

  calls = get_calls()
  assert length(calls) == 1
  [{messages, _opts}] = calls
  assert hd(messages).content == "hello"
end
```

### Simulating Errors

```elixir
set_responses([{:error, :rate_limited}])

assert {:error, :rate_limited} =
  AI.chat(messages, provider: :test, api_key: "test")
```

## Custom Providers

You can implement your own provider by implementing the provider behaviour callbacks
and passing the module directly as the `:provider` option:

```elixir
defmodule MyApp.CustomProvider do
  def chat(messages, opts) do
    # Your implementation
    {:ok, %PhoenixAI.Response{content: "custom"}}
  end

  # ... other required callbacks
end

AI.chat(messages, provider: MyApp.CustomProvider)
```

## Setting a Default Provider

Configure the application-wide default so you don't need to pass `provider:` every call:

```elixir
config :phoenix_ai, :default_provider, :anthropic
```

Then:

```elixir
# Uses :anthropic by default
{:ok, response} = AI.chat(messages)
```
