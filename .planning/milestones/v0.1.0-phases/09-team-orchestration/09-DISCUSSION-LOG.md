# Phase 9: Team Orchestration - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-31
**Phase:** 09-team-orchestration
**Areas discussed:** Agent Specs, Merge Function, API Pública, Tratamento de Falhas
**Language:** Portuguese (user preference), documentation in English

---

## Agent Specs

| Option | Description | Selected |
|--------|-------------|----------|
| Funções zero-arity | fn -> result end. Consistente com Pipeline. Idiomático Elixir. Task.async_stream mapeia cada fn. | ✓ |
| Keyword lists (Agent opts) | [provider: :openai, prompt: "..."]. Team cria Agent ad-hoc. Mais acoplado. | |
| PIDs de Agents existentes | Caller cria Agents antes, passa PIDs. Team chama Agent.prompt. | |

**User's choice:** Funções zero-arity
**Notes:** User asked about Laravel/AI approach and Elixir best practices. Laravel uses Agent objects (OOP). Elixir idiom is data + functions (Task.async_stream). User also clarified that Team is only parallel — sequential is Pipeline (Phase 8). These are complementary.

---

## Merge Function

| Option | Description | Selected |
|--------|-------------|----------|
| Lista de {:ok, _} | {:error, _} | Merge recebe TODOS os resultados como tuplas. Caller decide sobre falhas. | ✓ |
| Só valores de sucesso | Team filtra erros antes de chamar merge. Merge só recebe sucessos. | |
| Resultados + índice | Lista de {index, result} para ordem determinística. | |

**User's choice:** Lista completa de tuplas
**Notes:** Maximum transparency — merge sees everything including errors.

---

## API Pública

| Option | Description | Selected |
|--------|-------------|----------|
| Só Team.run/3 | Simples e direto. DSL não faz sentido para paralelo. YAGNI. | |
| DSL + Team.run/3 | Dual mode como Pipeline. use PhoenixAI.Team com agent :name do. | ✓ |

**User's choice:** DSL + Team.run/3
**Notes:** User chose DSL for consistency with Pipeline's dual mode pattern.

---

## Tratamento de Falhas

| Option | Description | Selected |
|--------|-------------|----------|
| Coleta todos, merge decide | Team SEMPRE espera todos. Resultados parciais vão para merge. | ✓ |
| Fail-fast: cancela restantes | Se qualquer agent falha, cancela os restantes. | |
| Configurável via opt | on_error: :collect ou :fail_fast. Caller escolhe. | |

**User's choice:** Coleta todos, merge decide
**Notes:** Consistent with merge receiving all tuples. No short-circuit.

---

## Claude's Discretion

- Task.async_stream wrapper implementation details
- Whether DSL macro reuses Pipeline macro code
- Merge macro storage mechanism
- Test strategy for concurrent scenarios

## Deferred Ideas

None — discussion stayed within phase scope
