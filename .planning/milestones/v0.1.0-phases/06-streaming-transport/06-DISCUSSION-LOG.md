# Phase 6: Streaming Transport - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-30
**Phase:** 06-streaming-transport
**Areas discussed:** Parser SSE, API de entrega de chunks, Wire format por provider, Estratégia de testes

---

## Parser SSE e gerenciamento de buffer

| Option | Description | Selected |
|--------|-------------|----------|
| Lib `server_sent_events` | Mantida pela comunidade, lida com fragmentação, testada em produção | ✓ |
| Parser custom | Zero dependências, ~50 linhas, controle total | |

**User's choice:** `server_sent_events`
**Notes:** Evita bugs sutis de fragmentação TCP, lib focada e pequena.

---

## API de entrega de chunks

### Assinatura da função

| Option | Description | Selected |
|--------|-------------|----------|
| Tudo via opts | `stream(msgs, on_chunk: fn -> end)` ou `stream(msgs, to: self())` | ✓ |
| Callback posicional | `stream(msgs, fn -> end, opts)` com PID via `:to` nas opts | |

**User's choice:** Tudo via opts
**Notes:** User perguntou sobre recomendação do ecossistema Phoenix/Elixir. Explicado que message passing (PID) é o padrão idiomático para operações assíncronas, com callback como conveniência. Default `to: self()` é o mais ergonômico.

### Retorno do stream

| Option | Description | Selected |
|--------|-------------|----------|
| `{:ok, %Response{}}` acumulado | Chunks em tempo real + resultado final para logging/billing | ✓ |
| Apenas `:ok` | Caller já processou tudo via chunks | |

**User's choice:** `{:ok, %Response{}}` com content acumulado
**Notes:** Segue padrão do Finch (retorna acc final) e do laravel/ai.

---

## Wire format por provider

| Option | Description | Selected |
|--------|-------------|----------|
| Cada adapter decide | `parse_chunk/1` retorna `%StreamChunk{finish_reason: "stop"}` no sentinel | ✓ |
| Módulo central decide | Parser SSE detecta sentinels, adapters só parsam deltas | |
| Claude's discretion | | |

**User's choice:** Cada adapter decide
**Notes:** Consistente com design estabelecido — cada adapter é dono do seu wire format.

---

## Estratégia de testes

### Parser SSE

| Option | Description | Selected |
|--------|-------------|----------|
| Combinação inline + fixtures | Strings inline para unit, fixtures binárias para fragmentação | ✓ |
| Só strings inline | Simplicidade | |

**User's choice:** Combinação
**Notes:** Cobertura completa sem over-engineering.

### Fluxo completo

| Option | Description | Selected |
|--------|-------------|----------|
| Mox only | Consistente com testes existentes, zero infra extra | ✓ |
| Mox + Bypass | Unit + integration com HTTP fake server | |

**User's choice:** Mox only
**Notes:** Finch e server_sent_events já são testados pelas suas próprias libs. Nosso trabalho é testar a cola.

---

## Claude's Discretion

- Estrutura de módulos internos para streaming
- Integração server_sent_events com Finch chunked callback
- Design do acumulador para Response final
- Delegação OpenRouter -> OpenAI para parse_chunk
- Organização de fixtures SSE

## Deferred Ideas

None — discussion stayed within phase scope
