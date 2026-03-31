# Getting Started

PhoenixAI is an Elixir library for integrating AI providers into your applications.
It provides a unified interface for chat, streaming, tool use, agents, pipelines, and teams.

## Installation

Add `phoenix_ai` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:phoenix_ai, "~> 0.1"}
  ]
end
```

Then fetch dependencies:

```bash
mix deps.get
```

## Configuration

### Environment Variables (Recommended)

Set your provider API keys as environment variables:

```bash
export OPENAI_API_KEY="sk-..."
export ANTHROPIC_API_KEY="sk-ant-..."
export OPENROUTER_API_KEY="sk-or-..."
```

PhoenixAI resolves these automatically — no config file required for basic usage.

### Application Config

You can also configure providers in `config/config.exs`:

```elixir
import Config

config :phoenix_ai, :default_provider, :openai

config :phoenix_ai, :openai,
  api_key: System.get_env("OPENAI_API_KEY"),
  model: "gpt-4o",
  temperature: 0.7

config :phoenix_ai, :anthropic,
  api_key: System.get_env("ANTHROPIC_API_KEY"),
  model: "claude-sonnet-4-5"
```

For secrets in production, use runtime config in `config/runtime.exs`:

```elixir
import Config

config :phoenix_ai, :openai,
  api_key: System.fetch_env!("OPENAI_API_KEY")
```

## Your First AI.chat/2 Call

The `AI` module is the primary entry point. Build a list of messages and call `AI.chat/2`:

```elixir
alias PhoenixAI.Message

messages = [
  %Message{role: :user, content: "What is the capital of Portugal?"}
]

{:ok, response} = AI.chat(messages, provider: :openai, model: "gpt-4o")

IO.puts(response.content)
# => "The capital of Portugal is Lisbon."
```

You can include a system message to set context:

```elixir
messages = [
  %Message{role: :system, content: "You are a geography tutor. Be concise."},
  %Message{role: :user, content: "What is the capital of Portugal?"}
]

{:ok, response} = AI.chat(messages, provider: :openai)
```

## Understanding %Response{}

A successful `AI.chat/2` call returns `{:ok, %PhoenixAI.Response{}}`:

```elixir
%PhoenixAI.Response{
  content: "The capital of Portugal is Lisbon.",   # Text response
  parsed: nil,                                      # Populated for structured output
  tool_calls: [],                                   # Populated when model calls tools
  usage: %{                                         # Token consumption
    prompt_tokens: 15,
    completion_tokens: 10,
    total_tokens: 25
  },
  finish_reason: "stop",                            # Why generation stopped
  model: "gpt-4o",                                  # Model used
  provider_response: %{}                            # Raw provider response
}
```

Accessing the response:

```elixir
{:ok, response} = AI.chat(messages, provider: :openai)

# Text content
response.content

# Token usage
response.usage.total_tokens

# Tool calls (if tools were provided)
response.tool_calls

# Structured output (if schema was provided)
response.parsed
```

## Error Handling

`AI.chat/2` returns `{:error, reason}` on failure:

```elixir
case AI.chat(messages, provider: :openai) do
  {:ok, response} ->
    IO.puts(response.content)

  {:error, {:missing_api_key, :openai}} ->
    IO.puts("Set the OPENAI_API_KEY environment variable")

  {:error, %PhoenixAI.Error{status: 429}} ->
    IO.puts("Rate limit exceeded — back off and retry")

  {:error, reason} ->
    IO.inspect(reason, label: "AI error")
end
```

## Streaming

Use `AI.stream/2` to receive response text incrementally:

```elixir
{:ok, _response} = AI.stream(
  [%Message{role: :user, content: "Tell me a short story"}],
  provider: :openai,
  on_chunk: fn chunk ->
    if chunk.delta, do: IO.write(chunk.delta)
  end
)
```

Or send chunks to another process:

```elixir
{:ok, _response} = AI.stream(
  messages,
  provider: :openai,
  to: self()
)

# Receive chunks in the current process
receive do
  {:phoenix_ai, {:chunk, %PhoenixAI.StreamChunk{delta: text}}} when not is_nil(text) ->
    IO.write(text)
end
```

## Next Steps

- [Provider Setup](provider-setup.md) — Configure OpenAI, Anthropic, OpenRouter, and the TestProvider
- [Agents & Tools](agents-and-tools.md) — Build stateful agents with tool calling
- [Pipelines & Teams](pipelines-and-teams.md) — Compose multi-step and parallel AI workflows
