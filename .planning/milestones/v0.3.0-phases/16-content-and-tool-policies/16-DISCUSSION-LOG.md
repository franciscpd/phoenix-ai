# Phase 16: Content and Tool Policies - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-04
**Phase:** 16-content-and-tool-policies
**Areas discussed:** ContentFilter hook contract, ToolPolicy validation timing

---

## ContentFilter Hook Contract

| Option | Description | Selected |
|--------|-------------|----------|
| Hook receives Request | (Request.t()) -> {:ok, Request.t()} or {:error, String.t()}. Consistent with check/2. | ✓ |
| Hook receives Message (PRD) | (Message.t()) -> {:ok, Message.t()} or {:error, String.t()}. Iterates per message. | |
| You decide | Claude chooses | (selected, chose Request-level) |

**User's choice:** You decide → Claude chose Request-level hooks
**Notes:** More consistent with check/2 contract. Hook can access metadata, assigns, full message list.

---

## ToolPolicy Validation Timing

| Option | Description | Selected |
|--------|-------------|----------|
| Runtime in check/2 | Validates at first execution. Raise ArgumentError. | |
| Via NimbleOptions (Phase 17) | Config-time validation only. | |
| Both runtime + config | check/2 validates always, NimbleOptions validates via config. Belt and suspenders. | ✓ |

**User's choice:** Both (runtime + config)
**Notes:** ToolPolicy must work standalone (runtime) and via config (NimbleOptions in Phase 17).

---

## Claude's Discretion

- Moduledoc content, helper organization
- Halt on first tool violation vs check all tools

## Deferred Ideas

None — discussion stayed within phase scope.
