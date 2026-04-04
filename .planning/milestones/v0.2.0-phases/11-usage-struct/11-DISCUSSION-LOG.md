# Phase 11: Usage Struct - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-03
**Phase:** 11-usage-struct
**Areas discussed:** Dispatch strategy, Nil/empty handling, API surface

---

## Dispatch Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Atom explícito | from_provider(:openai, raw_map) — each adapter passes its atom. Consistent with Error struct pattern. | ✓ |
| Auto-detect por chaves | from_provider(raw_map) — detects provider by map keys (prompt_tokens vs input_tokens). More resilient but fragile if providers change keys. | |
| Claude decide | Claude chooses based on codebase patterns | |

**User's choice:** Atom explícito (Recommended)
**Notes:** Consistent with existing Error struct pattern in the codebase.

---

## Nil/Empty Handling

| Option | Description | Selected |
|--------|-------------|----------|
| Usage zerado | %Usage{input_tokens: 0, output_tokens: 0, ...} — consumers can always access .usage without nil checks | ✓ |
| Retornar nil | nil when no usage — forces consumer to check, but more honest about data absence | |
| Claude decide | Claude chooses based on codebase patterns | |

**User's choice:** Usage zerado (Recommended)
**Notes:** Consistent with current Response.usage default of %{}.

---

## API Surface

| Option | Description | Selected |
|--------|-------------|----------|
| Pública: from_provider/2 | Public API with @doc — consumers creating custom providers need to normalize usage too | ✓ |
| Interna: from_provider/2 | Internal API (@doc false) — only built-in adapters use it | |
| Pública: parse/2 | Shorter name: Usage.parse(:openai, raw_map) — aligned with parse_response in providers | |

**User's choice:** Pública: from_provider/2 (Recommended)
**Notes:** Supports custom provider use case.

---

## Claude's Discretion

- Internal module organization
- Test structure and helper placement
- Guard clauses vs pattern matching

## Deferred Ideas

None
