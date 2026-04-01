# Phase 10: Developer Experience - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-31
**Phase:** 10-developer-experience
**Areas discussed:** TestProvider API, Telemetry events, NimbleOptions scope, ExDoc & Hex publish

---

## TestProvider API

| Option | Description | Selected |
|--------|-------------|----------|
| Híbrido | Queue FIFO como default + handler function override. Cobre 90% dos casos com queue simples, e permite lógica custom quando precisa | ✓ |
| Queue FIFO | Respostas pré-definidas consumidas em ordem. Simples e previsível | |
| Function handler | Máxima flexibilidade — dev define a lógica de resposta | |
| Você decide | Claude escolhe a melhor abordagem | |

**User's choice:** Híbrido (queue + handler)
**Notes:** None — clear selection

---

## Telemetry Events

| Option | Description | Selected |
|--------|-------------|----------|
| Span + eventos extras | Span para chat/stream (duração) + execute para eventos discretos como tool_call e pipeline_step. Máxima observabilidade | ✓ |
| Span-based | :telemetry.span/3 para chat/stream. Pattern padrão do ecossistema Elixir | |
| Execute puro | :telemetry.execute/3 em pontos específicos. Mais controle granular | |
| Você decide | Claude escolhe baseado nos patterns do ecossistema | |

**User's choice:** Span + eventos extras
**Notes:** Maximum observability preferred — spans for duration measurement on main operations, discrete events for tool calls and orchestration steps

---

## NimbleOptions Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Todas as public APIs | AI.chat/2, AI.stream/3, Agent.start_link/1, Pipeline.run/2, Team.run/3 — toda entrada pública validada | ✓ |
| Só entry points principais | AI.chat/2, AI.stream/3, Agent.start_link/1 — os 3 mais usados | |
| Centralizado em Config | Um schema central em PhoenixAI.Config | |
| Você decide | Claude escolhe o scope | |

**User's choice:** Todas as public APIs
**Notes:** Complete validation coverage — every public entry point gets NimbleOptions schema

---

## ExDoc & Hex Publish

| Option | Description | Selected |
|--------|-------------|----------|
| Completo com cookbook | 4 guides + cookbook com recipes (RAG pattern, multi-agent workflow, streaming UI) | ✓ |
| Guides essenciais | Getting Started + Provider Setup + Agent & Tools + Pipeline & Team. 4 guides focados | |
| Mínimo viável | Só README.md com examples + moduledocs básicos | |
| Você decide | Claude escolhe o nível de docs | |

**User's choice:** Completo com cookbook
**Notes:** Rich documentation with practical recipes to attract adoption

---

## Claude's Discretion

- TestProvider internal state management (Agent vs ETS)
- Exact telemetry metadata keys beyond provider/model/token_usage
- NimbleOptions schema style (@opts_schema vs inline)
- ExDoc theme and styling
- Cookbook recipe ordering and depth
- Hex publish checklist details

## Deferred Ideas

None — discussion stayed within phase scope
