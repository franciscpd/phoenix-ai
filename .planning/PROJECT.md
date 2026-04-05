# PhoenixAI

## What This Is

An Elixir library that provides a unified API for AI provider integration (OpenAI, Anthropic, OpenRouter) with tool calling, streaming, structured output, stateful agents, sequential pipelines, parallel team execution, normalized token usage, and pre-call guardrails — all built on BEAM/OTP concurrency primitives.

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
- ✓ Normalized `PhoenixAI.Usage` struct with `from_provider/2` factory — v0.2.0
- ✓ Auto-calculated `total_tokens` when provider omits it — v0.2.0
- ✓ `Response.usage` and `StreamChunk.usage` carry `Usage.t()` — v0.2.0
- ✓ All adapters normalize usage at parse time — v0.2.0
- ✓ Backward compatibility via `provider_specific` field — v0.2.0
- ✓ Policy behaviour with middleware-chain halt semantics — v0.3.0
- ✓ Request struct for guardrails pipeline context — v0.3.0
- ✓ PolicyViolation struct for structured error reporting — v0.3.0
- ✓ Pipeline executor with ordered policy chain — v0.3.0
- ✓ JailbreakDetector behaviour + default keyword-based implementation — v0.3.0
- ✓ JailbreakDetection policy with scope/threshold config — v0.3.0
- ✓ ContentFilter policy with pre/post user-provided function hooks — v0.3.0
- ✓ ToolPolicy with allowlist/denylist modes — v0.3.0
- ✓ Composable presets (:default, :strict, :permissive) — v0.3.0
- ✓ `Response.provider` field identifying originating provider atom — v0.3.1
- ✓ All adapters set `:provider` in `parse_response/1` — v0.3.1

### Active

(None — planning next milestone)

### Out of Scope

- Web UI or frontend components — this is a backend library
- Built-in persistence/database layer — consumers handle their own storage
- Specific business-logic skills (email, calendar) — consumers define their own
- Deployment tooling — standard Mix library distribution
- Embedding/vector search — separate concern, may be a future companion library
- Cost calculation helpers — consumer responsibility (e.g. phoenix_ai_store)
- Token counting / estimation — different concern, not part of usage normalization
- Usage aggregation / analytics — consumer-side feature, not runtime concern

## Context

- **Origin:** The author is building "Chico", a micro-SaaS personal assistant currently in Laravel using laravel/ai. Once validated, the plan is to port to Phoenix/Elixir for native concurrency and scalability.
- **Reference implementation:** [laravel/ai](https://github.com/laravel/ai) — the API surface and provider abstraction are the primary inspiration.
- **Current state:** v0.3.1 shipped. ~3,900 LOC lib, ~5,400 LOC tests, 422 tests passing. Published at https://hex.pm/packages/phoenix_ai.
- **PRD source:** Guardrails PRD defined in `phoenix_ai_store/.planning/phases/05-guardrails/BRAINSTORM.md` — stateless core policies go here, stateful policies (TokenBudget, CostBudget) stay in phoenix_ai_store.
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
| Usage normalization in adapters | Normalize at the closest point to raw data, not centrally | ✓ Good — clear boundaries |
| Explicit atom dispatch for Usage | `from_provider(:openai, raw)` consistent with Error struct pattern | ✓ Good — idiomatic multi-clause |
| OpenRouter own parse_chunk | Each adapter uses its own provider atom for consistency | ✓ Good — no delegation ambiguity |
| Generic fallback in from_provider | Unknown providers auto-detected by key conventions | ✓ Good — zero-config for OpenAI-compatible providers |
| Guardrails as stateless pure functions | No GenServer/ETS — policies run in caller's process | ✓ Good — OTP-idiomatic, no hidden state |
| JailbreakDetector behaviour decoupled from policy | Detector reports score+patterns, policy decides halt | ✓ Good — each independently testable with Mox |
| {:halt, violation} internal / {:error, violation} external | Struct type discriminates policy rejection from provider error | ✓ Good — clean boundary |
| Stateful policies deferred to phoenix_ai_store | TokenBudget/CostBudget need persistence layer | ✓ Good — keeps core library dependency-free |
| Provider field in adapters, not central dispatch | Each adapter owns its complete Response — consistent with Usage pattern | ✓ Good — no coupling to lib/ai.ex |
| Telemetry already has :provider | do_chat/2 sets meta with provider_atom from opts — no duplication needed | ✓ Good — avoided unnecessary scope |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd:transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---

*Last updated: 2026-04-05 after v0.3.1 milestone completion*
