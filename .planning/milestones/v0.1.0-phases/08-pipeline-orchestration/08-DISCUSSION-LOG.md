# Phase 8: Pipeline Orchestration - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-31
**Phase:** 08-pipeline-orchestration
**Areas discussed:** Step Definition, Input/Output Contract, Public API, Agent Integration
**Language:** Portuguese (user preference)

---

## Step Definition

| Option | Description | Selected |
|--------|-------------|----------|
| Funções anônimas | Padrão idiomático Elixir. fn input -> {:ok, result} end. Como Plug, Enum.reduce. | ✓ |
| Módulo com behaviour | PhoenixAI.Pipeline.Step com callbacks name/0, run/1. Mais estruturado. | |
| Tupla {mod, fun, args} | Estilo MFA do Erlang. Familiar para OTP mas menos legível. | |
| Híbrido: funções + módulos | Aceita ambos. Flexibilidade máxima, mais complexo. | |

**User's choice:** Funções anônimas
**Notes:** User asked about Elixir/Phoenix best practices first. Confirmed that functional composition (like Plug) is the idiomatic approach. Functions over behaviours for composition.

---

## Input/Output Contract

| Option | Description | Selected |
|--------|-------------|----------|
| Sempre %Response{} | Tipo fixo como Plug/%Conn{}. Facilita @spec e Dialyzer. | |
| Termo livre com @spec | Cada step define seu tipo. Contrato é a tupla ok/error. | ✓ |
| Mapa com contexto acumulado | Estilo Ecto.Multi com contexto acumulado entre steps. | |

**User's choice:** Termo livre com @spec (estilo Ecto.Multi)
**Notes:** User initially selected %Response{} fixo, then changed mind after considering that Elixir recommends flexible typing. Asked "No Elixir não é recomendado ter tipagens para facilitar entrada e saída?" — after discussing Ecto.Multi's approach, confirmed term-free as better fit. The contract is on the tuple shape ({:ok, _} / {:error, _}), not the internal type.

---

## Public API

| Option | Description | Selected |
|--------|-------------|----------|
| Pipeline.run(steps, input) | Função única, lista de steps, input inicial. Simples e direto. | |
| Builder pattern com pipe | Pipeline.new() |> Pipeline.step(fn...) |> Pipeline.run(input). | |
| Macro DSL | use PhoenixAI.Pipeline + step :name do. Declarativo, nomeado. | ✓ |

**User's choice:** Macro DSL
**Notes:** User chose DSL initially. Follow-up confirmed dual mode: DSL for reusable pipelines + Pipeline.run/2 for ad-hoc usage. Both modes use the same execution engine.

**Follow-up: DSL Scope**

| Option | Description | Selected |
|--------|-------------|----------|
| DSL + Pipeline.run/2 | Ambos: DSL para reutilizáveis, run/2 para ad-hoc. | ✓ |
| Só DSL | Todo pipeline é um módulo. Sem run/2 ad-hoc. | |

**User's choice:** DSL + Pipeline.run/2

---

## Agent Integration

| Option | Description | Selected |
|--------|-------------|----------|
| Steps chamam AI.chat diretamente | Pipeline agnóstico. Steps chamam o que quiserem. Zero acoplamento com Agent. | ✓ |
| Helpers para Agent no Pipeline | Pipeline.agent_step(pid) como conveniência. | |
| Pipeline cria Agents automático | Pipeline gerencia ciclo de vida de Agents. | |

**User's choice:** Steps chamam AI.chat diretamente
**Notes:** Pipeline has zero coupling to Agent. If consumer wants Agent, they call Agent.prompt/2 inside the step function.

---

## Claude's Discretion

- Internal macro implementation (`__using__`, `step` macro compilation)
- Run loop implementation (Enum.reduce_while vs recursion)
- Exact opts for Pipeline.run/3 v1
- Test strategy and fixtures
- DSL step options support

## Deferred Ideas

None — discussion stayed within phase scope
