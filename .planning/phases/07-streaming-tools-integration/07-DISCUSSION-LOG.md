# Phase 7: Streaming + Tools Integration - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-30
**Phase:** 07-streaming-tools-integration
**Areas discussed:** Tool call accumulation, Stream+Tool loop design, Tool chunk delivery, SSE fixture strategy

---

## Tool Call Accumulation

### Where to accumulate tool call deltas?

| Option | Description | Selected |
|--------|-------------|----------|
| No accumulator do Stream | Estender o acc map existente em Stream.run/4 com campos tool_calls_in_progress. Mesmo padrao do content accumulation. | Yes |
| No parse_chunk/1 do adapter | Cada adapter mantem estado interno para acumular tool calls. parse_chunk/1 passa a ser stateful. | |
| Modulo dedicado ToolCallAccumulator | Um modulo separado que recebe deltas e retorna tool calls completos. | |

**User's choice:** No accumulator do Stream (Recommended)
**Notes:** Consistent with existing accumulator pattern. No interface changes needed.

### How should parse_chunk/1 signal tool call deltas?

| Option | Description | Selected |
|--------|-------------|----------|
| Via StreamChunk.tool_call_delta | parse_chunk/1 popula o campo tool_call_delta ja existente no struct. Zero mudanca na interface. | Yes |
| Novo struct ToolCallChunk | Um struct separado para tool call deltas. Mais explicito mas muda o contrato. | |

**User's choice:** Via StreamChunk.tool_call_delta (Recommended)
**Notes:** Field already exists in struct since Phase 6. Forward-compatibility confirmed.

---

## Stream+Tool Loop Design

### How to structure the streaming + tools loop?

| Option | Description | Selected |
|--------|-------------|----------|
| Estender Stream.run/4 | Adicionar logica de tool loop DENTRO de Stream.run/4 (ou wrapper). Reutiliza toda a infra de streaming. | Yes |
| Novo StreamToolLoop module | Modulo dedicado que orquestra Stream.run/4 + tool execution. Paralelo ao ToolLoop existente. | |
| Unificar ToolLoop | Fazer ToolLoop.run/4 aceitar :stream option. Um unico loop para ambos. | |

**User's choice:** Estender Stream.run/4 (Recommended)
**Notes:** No new module needed. Reuses all existing streaming infrastructure.

### Should re-calls after tool execution also be streaming?

| Option | Description | Selected |
|--------|-------------|----------|
| Sim, sempre streaming | Todas as chamadas no loop sao streaming. Consistencia. | Yes |
| So a primeira e streaming | Apos tool execution, re-chama com chat/2 (sincrono). | |

**User's choice:** Sim, sempre streaming (Recommended)
**Notes:** Consumer expects streaming all the way through if they asked for stream.

---

## Tool Chunk Delivery

### Should callback/PID receive tool_call_delta chunks?

| Option | Description | Selected |
|--------|-------------|----------|
| Sim, entregar tudo | O callback recebe %StreamChunk{} com tool_call_delta populado. Maxima transparencia. | Yes |
| So texto, filtrar tool deltas | Chunks com tool_call_delta sao acumulados internamente mas NAO entregues ao callback. | |
| Configuravel via opt | Nova opt :include_tool_chunks (default true). Flexivel mas mais API surface. | |

**User's choice:** Sim, entregar tudo (Recommended)
**Notes:** Maximum transparency. Consumer decides what to display.

---

## SSE Fixture Strategy

### How to structure streaming + tools fixtures?

| Option | Description | Selected |
|--------|-------------|----------|
| Arquivos .sse gravados | Mesma estrategia da Phase 6. Novos arquivos em test/fixtures/sse/. Reproduzivel. | Yes |
| Inline nos testes | Strings inline nos testes. Mais visivel mas verbose para payloads complexos. | |
| Mix dos dois | Fixtures .sse para fluxos completos, inline para edge cases. | |

**User's choice:** Arquivos .sse gravados (Recommended)
**Notes:** Consistent with Phase 6 approach. New files for tool call scenarios.

---

## Claude's Discretion

- Internal helper functions for assembling tool call fragments
- Whether stream_with_tools is separate function or integrated via opts detection
- How tool execution integrates with accumulator reset between iterations
- Exact structure of tool_call_delta map fields per provider
- Whether OpenRouter gets its own tool call fixture or reuses OpenAI's

## Deferred Ideas

None — discussion stayed within phase scope
