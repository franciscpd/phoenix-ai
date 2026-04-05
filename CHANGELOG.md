# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-04-04

### Added

- **Guardrails pipeline** — `Guardrails.Pipeline.run/2` executes an ordered list of policies against a request, halting on the first violation
- **Policy behaviour** — `Guardrails.Policy` defines the `check/2` callback contract for all guardrail policies
- **Request struct** — `Guardrails.Request` carries messages, tool calls, metadata, and inter-policy assigns through the pipeline
- **PolicyViolation struct** — Machine-readable violation with policy module, reason, message, and metadata
- **Jailbreak detection** — `JailbreakDetector` behaviour with a built-in keyword-based default detector (role override, instruction override, DAN patterns, base64 evasion)
- **JailbreakDetection policy** — Configurable `:threshold`, `:scope`, and `:detector` options for jailbreak scanning
- **ContentFilter policy** — Pre/post function hooks for custom content inspection and transformation
- **ToolPolicy** — Allow/deny list enforcement for tool calls with structured violation reporting
- **Pipeline presets** — `Pipeline.preset(:default | :strict | :permissive)` for quick configuration
- **Pipeline config** — `Pipeline.from_config/1` with NimbleOptions validation for `preset`, `policies`, `jailbreak_threshold`, `jailbreak_scope`, and `jailbreak_detector`
- **Guardrails telemetry** — Pipeline span (`:start`/`:stop`/`:exception`), per-policy `:start`/`:stop` events, and jailbreak `:detected` event
- **Guardrails guide** — ExDoc guide with usage examples, custom policies, and telemetry documentation

## [0.2.0] - 2026-04-03

### Added

- `PhoenixAI.Usage` struct for normalized token usage tracking across all providers
- Usage integration in `Response`, `StreamChunk`, and stream accumulator
- Per-provider usage parsing: OpenAI, Anthropic, OpenRouter

### Changed

- Telemetry events now include `%Usage{}` struct in metadata
- `TestProvider` updated to return `%Usage{}` in fixtures

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
