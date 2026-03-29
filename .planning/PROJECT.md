# PhoenixAI

## What This Is

An Elixir library that brings an AI integration layer to the Phoenix ecosystem, inspired by [laravel/ai](https://github.com/laravel/ai). PhoenixAI provides a unified API for interacting with multiple AI providers, defining skills as tool calls, composing sequential pipelines, and running parallel async agents — all leveraging the BEAM/OTP concurrency model.

## Core Value

Developers can build AI-powered agents with skills, sequential pipelines, and parallel execution using idiomatic Elixir/Phoenix patterns and BEAM concurrency primitives.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Multi-provider support (OpenAI, Anthropic, OpenRouter) with a unified API
- [ ] Provider-agnostic message/conversation abstraction
- [ ] Structured output (schema validation for AI responses)
- [ ] Skills as tool calls (function calling / tool use)
- [ ] Sequential pipeline execution (skill A feeds into skill B)
- [ ] Parallel agent execution using OTP (GenServer/Task.async)
- [ ] Streaming support for real-time responses
- [ ] Conversation history / context management
- [ ] Configurable per-provider settings (API keys, models, parameters)
- [ ] Extensible provider architecture (easy to add new providers)

### Out of Scope

- Web UI or frontend components — this is a backend library
- Built-in persistence/database layer — consumers handle their own storage
- Specific business-logic skills (email, calendar) — consumers define their own
- Deployment tooling — standard Mix library distribution
- Embedding/vector search — separate concern, may be a future companion library

## Context

- **Origin:** The author is building "Chico", a micro-SaaS personal assistant currently in Laravel using laravel/ai. Once validated, the plan is to port to Phoenix/Elixir for native concurrency and scalability.
- **Reference implementation:** [laravel/ai](https://github.com/laravel/ai) — the API surface and provider abstraction are the primary inspiration.
- **Ecosystem gap:** Elixir lacks a comprehensive, Laravel/AI-style library that unifies multiple providers with tool calling, pipelines, and agent patterns.
- **BEAM advantage:** GenServers for long-running agents, Task.async for parallel execution, Supervisors for fault-tolerant pipelines — these are native to the platform and should be first-class in the library design.
- **Use case patterns:**
  - Individual skill calls (e.g., "schedule a meeting" → tool call)
  - Sequential pipelines (web search → write script → plan social content)
  - Parallel agents (multiple independent tasks running concurrently, results merged)

## Constraints

- **Tech stack**: Elixir, Mix library, Phoenix-compatible but not Phoenix-dependent
- **Providers v1**: OpenAI, Anthropic, OpenRouter — must ship with all three
- **API parity goal**: Feature parity with laravel/ai where applicable, adapted to Elixir idioms
- **Open source**: Designed for community contribution from day one (English docs, clear architecture)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Elixir library (not Phoenix-specific) | Broader adoption — works with any Elixir app, not just Phoenix | -- Pending |
| English documentation | Open-source community contribution | -- Pending |
| Multi-provider from v1 | Author's immediate need (OpenAI + Anthropic + OpenRouter) | -- Pending |
| Inspired by laravel/ai, not a port | Adapt to Elixir/OTP idioms rather than mirroring PHP patterns | -- Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd:transition`):
1. Requirements invalidated? -> Move to Out of Scope with reason
2. Requirements validated? -> Move to Validated with phase reference
3. New requirements emerged? -> Add to Active
4. Decisions to log? -> Add to Key Decisions
5. "What This Is" still accurate? -> Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-03-29 after initialization*
