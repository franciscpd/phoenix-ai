# PhoenixAI

[![Hex.pm](https://img.shields.io/hexpm/v/phoenix_ai.svg)](https://hex.pm/packages/phoenix_ai)
[![Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/phoenix_ai)

AI integration library for Elixir inspired by [laravel/ai](https://github.com/laravel/ai).

PhoenixAI provides a unified API for interacting with multiple AI providers, defining tools, composing sequential pipelines, and running parallel agents — all leveraging the BEAM/OTP concurrency model.

## Features

- **Multi-provider support** — OpenAI, Anthropic, and OpenRouter with a unified API
- **Tool calling** — Define tools as modules, automatic tool loop execution
- **Streaming** — Real-time token streaming with backpressure support
- **Structured output** — JSON schema validation for AI responses
- **Agents** — Stateful GenServer-based agents with conversation history
- **Pipelines** — Sequential step composition with context passing
- **Teams** — Parallel agent execution using `Task.async_stream`
- **Guardrails** — Pre-call policy pipeline with jailbreak detection, content filtering, and tool allowlists/denylists
- **Telemetry** — Built-in `:telemetry` spans for observability
- **TestProvider** — Offline testing with scripted responses

## Installation

Add `phoenix_ai` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:phoenix_ai, "~> 0.3.0"}
  ]
end
```

## Quick Start

```elixir
# Configure a provider
config :phoenix_ai,
  provider: :openai,
  openai: [
    api_key: System.get_env("OPENAI_API_KEY"),
    model: "gpt-4o-mini"
  ]

# Simple chat
{:ok, response} = AI.chat([
  %{role: "user", content: "Hello!"}
])

IO.puts(response.content)
```

## Documentation

- [Getting Started](https://hexdocs.pm/phoenix_ai/getting-started.html)
- [Provider Setup](https://hexdocs.pm/phoenix_ai/provider-setup.html)
- [Agents and Tools](https://hexdocs.pm/phoenix_ai/agents-and-tools.html)
- [Pipelines and Teams](https://hexdocs.pm/phoenix_ai/pipelines-and-teams.html)
- [Guardrails](https://hexdocs.pm/phoenix_ai/guardrails.html)

## License

MIT License — see [LICENSE](LICENSE) for details.
