# Phase 1: Core Foundation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-29
**Phase:** 01-core-foundation
**Areas discussed:** Naming & API surface, Configuration, Provider behaviour, Mix project setup

---

## Naming & API Surface

### Package Name

| Option | Description | Selected |
|--------|-------------|----------|
| phoenix_ai (Recommended) | Aligned with project name. Module: PhoenixAI | Yes |
| ex_ai | Convention 'ex_' prefix. Module: ExAI | |
| ai_ex | Inversion for 'ai' priority. Module: AiEx | |

**User's choice:** phoenix_ai
**Notes:** None

### Main API Module

| Option | Description | Selected |
|--------|-------------|----------|
| PhoenixAI.chat/2 | Main module as namespace | |
| AI.chat/2 | Short, inspired by laravel/ai AI::agent() | Yes |
| PhoenixAI.AI.chat/2 | Separated namespace | |

**User's choice:** AI.chat/2
**Notes:** None

### Struct Naming

| Option | Description | Selected |
|--------|-------------|----------|
| PhoenixAI.Message (Recommended) | Flat: PhoenixAI.Message, PhoenixAI.Response | Yes |
| PhoenixAI.Types.Message | Types namespace | |
| PhoenixAI.Schema.Message | Schema namespace | |

**User's choice:** PhoenixAI.Message (flat)
**Notes:** None

---

## Configuration

### Config Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Call-site first (Recommended) | Call-site > config.exs > env vars | Yes |
| Config.exs first | Centralized in config | |
| Struct-based | Explicit client struct | |

**User's choice:** Call-site first
**Notes:** None

### Multi-tenant

| Option | Description | Selected |
|--------|-------------|----------|
| Sim (Recommended) | Call-site options resolve naturally | Yes |
| Nao, v2 | One global API key per provider | |

**User's choice:** Yes, from v1
**Notes:** None

### Env Vars

| Option | Description | Selected |
|--------|-------------|----------|
| Sim, com System.get_env (Recommended) | OPENAI_API_KEY as automatic fallback | Yes |
| Nao, apenas config/call-site | Consumer handles env vars | |

**User's choice:** Yes, automatic env var fallback
**Notes:** None

### Default Models

| Option | Description | Selected |
|--------|-------------|----------|
| Default por provider (Recommended) | OpenAI: gpt-4o, Anthropic: claude-sonnet-4-5 | Yes |
| Sempre explicito | No defaults | |
| Configuravel | Consumer defines defaults | |

**User's choice:** Default per provider
**Notes:** Anthropic models should use short IDs without date suffix (claude-sonnet-4-5, not claude-sonnet-4-5-20250514)

### Provider Reference

| Option | Description | Selected |
|--------|-------------|----------|
| Atom shortcut (Recommended) | provider: :openai — lib resolves to module | Yes |
| Modulo direto | provider: PhoenixAI.Providers.OpenAI | |
| Ambos | Atom or module accepted | |

**User's choice:** Atom shortcut
**Notes:** None

---

## Provider Behaviour

### Callback Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Core obrigatorio + opcionais (Recommended) | chat/2 required, stream/3 optional | Yes |
| Todos obrigatorios | All callbacks required | |
| Multiplos behaviours | Separate composable behaviours | |

**User's choice:** Core required + optional callbacks
**Notes:** None

### Escape Hatch

| Option | Description | Selected |
|--------|-------------|----------|
| provider_options map (Recommended) | Explicit passthrough map | Yes |
| Keyword opts passthrough | Unknown opts pass through | |
| Provider-specific modules | Direct provider calls | |

**User's choice:** provider_options map
**Notes:** None

---

## Mix Project Setup

### Elixir Version

| Option | Description | Selected |
|--------|-------------|----------|
| ~> 1.17 (Recommended) | Good compatibility | |
| ~> 1.18 | Can use stdlib JSON | Yes |
| ~> 1.16 | Maximum compatibility | |

**User's choice:** ~> 1.18
**Notes:** Enables stdlib JSON module usage

### Test Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Mox + fixtures (Recommended) | Behaviour mocking + recorded responses | Yes |
| Bypass | HTTP simulation | |
| Ambos | Mox for unit + Bypass for integration | |

**User's choice:** Mox + fixtures
**Notes:** None

### CI

| Option | Description | Selected |
|--------|-------------|----------|
| GitHub Actions (Recommended) | Full CI pipeline | Yes |
| Sem CI por agora | Add CI later | |

**User's choice:** GitHub Actions from day one
**Notes:** None

### Directory Structure

| Option | Description | Selected |
|--------|-------------|----------|
| Standard Mix lib (Recommended) | lib/phoenix_ai/ with providers/ | Yes |
| Flat lib/ | Everything in lib/phoenix_ai/ | |

**User's choice:** Standard Mix lib
**Notes:** None

### Quality Tools

| Option | Description | Selected |
|--------|-------------|----------|
| Credo | Linting and style | Yes |
| Dialyzer/Dialyxir | Static type checking | Yes |
| mix format | Auto-formatting | Yes |
| ExCoveralls | Test coverage reports | Yes |

**User's choice:** All four tools
**Notes:** None

---

## Claude's Discretion

- Exact Req wrapper implementation details
- Internal module organization beyond declared structure
- NimbleOptions schema definitions
- ExDoc configuration

## Deferred Ideas

None — discussion stayed within phase scope
