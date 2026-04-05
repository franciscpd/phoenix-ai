# Phase 18: Provider Field - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-05
**Phase:** 18-provider-field
**Areas discussed:** TestProvider, Telemetry

---

## TestProvider

| Option | Description | Selected |
|--------|-------------|----------|
| Merge no parse_response | parse_response(body) passa a fazer %{body \| provider: :test} — consistente com o padrão dos outros adapters | ✓ |
| Setar no chat/2 | Depois de obter a response do handler/responses, fazer Map.put(response, :provider, :test) | |
| Consumer seta | Deixar quem configura o TestProvider incluir :provider no %Response{} — mais flexível mas quebra consistência | |

**User's choice:** Merge no parse_response (Recommended)
**Notes:** Maintains consistency with other adapters — all set :provider in parse_response/1

---

## Telemetry

| Option | Description | Selected |
|--------|-------------|----------|
| Sim, incluir | Adicionar provider ao metadata de [:phoenix_ai, :chat, :stop] — útil para o phoenix_ai_store capturar via telemetry handler | ✓ |
| Não, só Response | Manter escopo mínimo — o consumer pode ler response.provider diretamente | |

**User's choice:** Sim, incluir
**Notes:** Enables cost tracking via telemetry handler pattern, which phoenix_ai_store already uses

---

## Claude's Discretion

- Exact placement of :provider in defstruct field order
- Whether to also add :provider to [:phoenix_ai, :chat, :start] telemetry event

## Deferred Ideas

None
