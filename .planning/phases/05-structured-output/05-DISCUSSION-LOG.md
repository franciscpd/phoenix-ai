# Phase 5: Structured Output - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-30
**Phase:** 05-structured-output
**Areas discussed:** Definicao de Schema, API publica e integracao, Traducao por provider, Validacao e erros

---

## Definicao de Schema

| Option | Description | Selected |
|--------|-------------|----------|
| Plain map (Recomendado) | Mesmo padrao do Tool.parameters_schema. Reutiliza to_json_schema/1. | |
| Modulo com behaviour | PhoenixAI.Schema behaviour com callbacks output_schema/0 e cast/1. | |
| Ambos (map + behaviour) | Aceitar plain map para casos simples e behaviour para cast/validacao custom. Plug-like dispatch. | ✓ |
| Voce decide | Claude escolhe baseado nos padroes do codebase. | |

**User's choice:** Ambos (map + behaviour)
**Notes:** User asked about Elixir/Phoenix philosophy first. After explanation of Plug-like patterns (module OR function/data), chose dual interface.

### Sub-question: Cast callback

| Option | Description | Selected |
|--------|-------------|----------|
| Sim, cast/1 opcional | Behaviour defines schema/0 + cast/1 (@optional_callback). | |
| Nao, so schema/0 | Keeps simple — just schema, validation/cast is consumer responsibility. | |
| Voce decide | Claude decides based on complexity vs utility. | ✓ |

**User's choice:** Voce decide
**Notes:** Claude has discretion on whether to include optional cast/1 callback.

### Sub-question: Map format

| Option | Description | Selected |
|--------|-------------|----------|
| Sim, mesmo formato (Recomendado) | Same as Tool.parameters_schema — atom keys, JSON Schema structure. Reuses to_json_schema/1. | ✓ |
| Formato simplificado | Shorter schema without JSON Schema verbosity. Needs extra conversion. | |
| Voce decide | Claude chooses most consistent format. | |

**User's choice:** Sim, mesmo formato
**Notes:** Consistency with existing Tool.parameters_schema pattern was the deciding factor.

---

## API Publica e Integracao

| Option | Description | Selected |
|--------|-------------|----------|
| Opcao :schema (Recomendado) | AI.chat(msgs, schema: ...). Simple, direct, parallel to :tools. | ✓ |
| Opcao :response_format | Follows OpenAI naming. Couples to provider naming. | |
| Voce decide | Claude chooses most idiomatic name. | |

**User's choice:** Opcao :schema
**Notes:** Provider-agnostic naming preferred.

### Sub-question: Return location

| Option | Description | Selected |
|--------|-------------|----------|
| Campo :parsed no Response (Recomendado) | New parsed: field on Response struct. content keeps raw JSON, parsed has decoded map. | ✓ |
| Wrapper separado | Returns {:ok, %StructuredResponse{...}} — different type for structured output. | |
| So no content | No new field. Consumer does Jason.decode! themselves. | |

**User's choice:** Campo :parsed no Response
**Notes:** Backward compatible — existing code using content is unaffected.

### Sub-question: Agent integration

| Option | Description | Selected |
|--------|-------------|----------|
| Ambos (Recomendado) | Agent accepts :schema in start_link. Every Agent response includes parsed. | ✓ |
| So AI.chat/2 | Agent doesn't support schema in this phase. | |
| Voce decide | Claude decides based on SCHEMA-01-04 scope. | |

**User's choice:** Ambos
**Notes:** Agent already delegates to ToolLoop/chat, so schema support flows naturally.

### Sub-question: Schema + Tools coexistence

| Option | Description | Selected |
|--------|-------------|----------|
| Sim, coexistem (Recomendado) | Schema validates final response after tool loop completes. Both can be passed simultaneously. | ✓ |
| Nao, mutuamente exclusivos | Use schema OR tools, never both. | |
| Voce decide | Claude decides based on implementation complexity. | |

**User's choice:** Sim, coexistem
**Notes:** Natural separation — tools resolve actions, schema guarantees final response format.

---

## Traducao por Provider

| Option | Description | Selected |
|--------|-------------|----------|
| Tool use forcado (Recomendado) | Creates internal "structured_output" tool with input_schema = user's schema. tool_choice: any. Most reliable. | ✓ |
| Prefill + system prompt | System prompt instructs JSON. Assistant prefilled with '{'. More fragile. | |
| Voce decide | Claude chooses most reliable strategy. | |

**User's choice:** Tool use forcado (for Anthropic)
**Notes:** OpenAI uses native response_format. Anthropic has no native support, so forced tool_use is the standard workaround.

### Sub-question: Schema + Tools on Anthropic

| Option | Description | Selected |
|--------|-------------|----------|
| Schema como tool extra (Recomendado) | "structured_output" appended to user's tool list. tool_choice: auto. Adapter extracts when model calls it. | ✓ |
| Duas fases separadas | First run tool loop, then second call with only schema tool. Extra API call. | |
| Voce decide | Claude decides most pragmatic strategy. | |

**User's choice:** Schema como tool extra
**Notes:** Single-pass approach — no extra API call. Model calls structured_output when done with real tools.

---

## Validacao e Erros

| Option | Description | Selected |
|--------|-------------|----------|
| Erro imediato (Recomendado) | {:error, {:validation_failed, details}} with field-level detail. No auto-retry. Consumer decides. | ✓ |
| Retry automatico | Retry up to N times, send error back to model. Hides API costs. | |
| Retorna ambos | {:ok, %Response{parsed: nil, validation_error: details}}. Less disruptive. | |
| Voce decide | Claude decides based on SCHEMA-04. | |

**User's choice:** Erro imediato
**Notes:** Follows SCHEMA-04: "never silently passes". Consumer controls retry logic.

### Sub-question: Invalid JSON error

| Option | Description | Selected |
|--------|-------------|----------|
| {:error, :invalid_json} (Recomendado) | Specific error for JSON parse failure. Distinct from :validation_failed. Two clear error types. | ✓ |
| Mesmo erro generico | Everything is {:error, :validation_failed}. Consumer doesn't distinguish. | |
| Voce decide | Claude decides error granularity. | |

**User's choice:** {:error, :invalid_json}
**Notes:** Three distinct error types: :invalid_json (not JSON), :validation_failed (wrong shape), %Error{} (network/provider).

### Sub-question: Validation depth

| Option | Description | Selected |
|--------|-------------|----------|
| Required + tipos (Recomendado) | Required keys, basic types, enum values, recursive nested objects. No min/max, pattern, $ref. | ✓ |
| So required keys | Minimal — only checks required keys exist. No type checking. | |
| Full JSON Schema | Complete JSON Schema validator. allOf, oneOf, $ref. Complex. | |
| Voce decide | Claude decides adequate level for v1. | |

**User's choice:** Required + tipos
**Notes:** Covers 90% of use cases. No external dependency needed. Recursive for nested objects.

---

## Claude's Discretion

- Whether PhoenixAI.Schema behaviour includes optional cast/1 callback
- Internal validation module structure
- Synthetic tool naming to avoid collision

## Deferred Ideas

None — discussion stayed within phase scope
