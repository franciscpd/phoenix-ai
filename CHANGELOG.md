# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-03-31

### Added

- Multi-provider support: OpenAI, Anthropic, OpenRouter
- Unified `AI.chat/2` and `AI.stream/2` API
- Tool calling with automatic tool loop execution
- Structured output with JSON schema validation
- Stateful `Agent` GenServer with conversation history
- Sequential `Pipeline` composition with context passing
- Parallel `Team` execution using `Task.async_stream`
- Real-time streaming with backpressure support
- `:telemetry` spans for chat, stream, tool calls, pipeline steps, and team completion
- `NimbleOptions` validation for all public APIs
- `TestProvider` for offline testing with scripted responses
- `PhoenixAI.Test` ExUnit helper module
- ExDoc guides: Getting Started, Provider Setup, Agents and Tools, Pipelines and Teams
- Cookbook recipes: RAG Pipeline, Multi-Agent Team, Streaming LiveView, Custom Tools
