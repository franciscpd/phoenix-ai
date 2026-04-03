# PhoenixAI

## What This Is

An Elixir library that provides a unified API for AI provider integration (OpenAI, Anthropic, OpenRouter) with tool calling, streaming, structured output, stateful agents, sequential pipelines, and parallel team execution — all built on BEAM/OTP concurrency primitives.

## Core Value

Developers can build AI-powered agents with skills, sequential pipelines, and parallel execution using idiomatic Elixir/Phoenix patterns and BEAM concurrency primitives.

## Requirements

### Validated

- ✓ Multi-provider support (OpenAI, Anthropic, OpenRouter) with a unified API — v0.1.0
- ✓ Provider-agnostic message/conversation abstraction — v0.1.0
- ✓ Structured output (schema validation for AI responses) — v0.1.0
- ✓ Skills as tool calls (function calling / tool use) — v0.1.0
- ✓ Sequential pipeline execution (skill A feeds into skill B) — v0.1.0
- ✓ Parallel agent execution using OTP (GenServer/Task.async) — v0.1.0
- ✓ Streaming support for real-time responses — v0.1.0
- ✓ Conversation history / context management — v0.1.0
- ✓ Configurable per-provider settings (API keys, models, parameters) — v0.1.0
- ✓ Extensible provider architecture (easy to add new providers) — v0.1.0

### Active

#### Current Milestone: v0.2.0 Usage Normalization

**Goal:** Normalize token usage data across all providers into a unified `PhoenixAI.Usage` struct, eliminating per-consumer normalization burden.

**Target features:**
- `PhoenixAI.Usage` struct with normalized fields
- `Usage.from_provider/2` mapping function per provider
- `Response.usage` type changed from `map()` to `Usage.t()`
- `StreamChunk.usage` normalized with the same struct
- Backward compatibility via `provider_specific` field

### Out of Scope

- Web UI or frontend components — this is a backend library
- Built-in persistence/database layer — consumers handle their own storage
- Specific business-logic skills (email, calendar) — consumers define their own
- Deployment tooling — standard Mix library distribution
- Embedding/vector search — separate concern, may be a future companion library

## Context

- **Origin:** The author is building "Chico", a micro-SaaS personal assistant currently in Laravel using laravel/ai. Once validated, the plan is to port to Phoenix/Elixir for native concurrency and scalability.
- **Reference implementation:** [laravel/ai](https://github.com/laravel/ai) — the API surface and provider abstraction are the primary inspiration.
- **Current state:** v0.1.0 shipped to Hex. 2,647 LOC lib, 4,555 LOC tests, 311 tests passing. Published at https://hex.pm/packages/phoenix_ai.
- **Tech stack:** Elixir, Req (sync HTTP), Finch (SSE streaming), Jason, NimbleOptions, Telemetry.

## Constraints

- **Tech stack**: Elixir, Mix library, Phoenix-compatible but not Phoenix-dependent
- **Providers v1**: OpenAI, Anthropic, OpenRouter — shipped with all three
- **API parity goal**: Feature parity with laravel/ai where applicable, adapted to Elixir idioms
- **Open source**: Designed for community contribution from day one (English docs, clear architecture)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Elixir library (not Phoenix-specific) | Broader adoption — works with any Elixir app | ✓ Good — no Phoenix dependency |
| English documentation | Open-source community contribution | ✓ Good — ExDoc + guides in English |
| Multi-provider from v1 | Author's immediate need (OpenAI + Anthropic + OpenRouter) | ✓ Good — all 3 shipped |
| Inspired by laravel/ai, not a port | Adapt to Elixir/OTP idioms rather than mirroring PHP patterns | ✓ Good — GenServer agents, Task.async teams |
| Finch for SSE, Req for sync | Two-path design: Req for simple chat, Finch for long-running streams | ✓ Good — clean separation |
| No auto-starting processes | Expose child_spec/1, let consumers own supervision tree | ✓ Good — OTP-idiomatic |
| Streaming splits Phase 6/7 | Combined streaming+tools must be tested as unit | ✓ Good — caught integration bugs |
| Per-provider tool result injection | OpenAI vs Anthropic wire formats differ significantly | ✓ Good — clean adapters |

## Evolution

This document evolves at phase transitions and milestone boundaries.

---
*Last updated: 2026-04-03 after v0.2.0 milestone start*
