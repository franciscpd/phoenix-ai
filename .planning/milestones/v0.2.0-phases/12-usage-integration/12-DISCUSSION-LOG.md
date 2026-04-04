# Phase 12: Usage Integration - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-03
**Phase:** 12-usage-integration
**Areas discussed:** Stream accumulator logic, Telemetry metadata, Test impact / backward compat

---

## Stream Accumulator Logic

| Option | Description | Selected |
|--------|-------------|----------|
| Manter || como está | The || works: chunk.usage is nil for intermediary and Usage.t() for final. In build_response, swap `acc.usage \|\| %{}` for `acc.usage \|\| %Usage{}`. | |
| Usar lógica explícita | Replace `chunk.usage \|\| acc.usage` with explicit pattern match or nil check. Avoids relying on || truthiness with structs. | ✓ |
| Claude decide | Claude chooses based on simplicity | |

**User's choice:** Usar lógica explícita
**Notes:** User prefers explicit logic over relying on || truthiness behavior with structs.

---

## Telemetry Metadata

| Option | Description | Selected |
|--------|-------------|----------|
| Passar struct direto | Consumer gets %Usage{} — more type-safe, access .input_tokens directly. Simplifies code (removes `\|\| %{}`). | ✓ |
| Converter pra map | Map.from_struct(usage) in telemetry — maintains backward compat for consumers doing `usage["prompt_tokens"]`. But no one uses that yet. | |
| Claude decide | | |

**User's choice:** Passar struct direto (Recommended)
**Notes:** No existing telemetry consumers to break.

---

## Test Impact / Backward Compat

| Option | Description | Selected |
|--------|-------------|----------|
| Atualizar inline | Change each assertion directly to use Usage.t() fields (.input_tokens, .output_tokens). Simple, direct, no abstractions. | ✓ |
| Criar helper de asserção | Create assert_usage(response, expected) that verifies the struct. More DRY but adds indirection. | |

**User's choice:** Atualizar inline (Recommended)
**Notes:** ~13 assertions across 6 test files need updating.

---

## Claude's Discretion

- Order of file modifications within each task
- Whether to update provider_contract_test.exs assertion (is_map still passes for structs)

## Deferred Ideas

None
