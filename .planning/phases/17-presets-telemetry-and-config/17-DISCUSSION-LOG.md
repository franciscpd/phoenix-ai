# Phase 17: Presets, Telemetry, and Config - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.

**Date:** 2026-04-04
**Phase:** 17-presets-telemetry-and-config
**Areas discussed:** Preset location, Telemetry approach, NimbleOptions integration

---

## Preset Location

| Option | Description | Selected |
|--------|-------------|----------|
| In Pipeline module | Pipeline.preset(:default) — coesa API | ✓ (Claude) |
| Separate Presets module | Guardrails.Presets.resolve(:default) | |

**User's choice:** You decide → Claude chose Pipeline module

---

## Telemetry Approach

| Option | Description | Selected |
|--------|-------------|----------|
| span for pipeline + execute per policy | Consistent with codebase: AI.chat uses span, pipeline.step uses execute | ✓ |
| execute for everything | Simpler but less structured | |

**User's choice:** span + execute (recommended)

---

## NimbleOptions Integration

| Option | Description | Selected |
|--------|-------------|----------|
| Standalone Pipeline.from_config/1 | Validates guardrails opts, returns policy list. No AI.chat/2 changes. | ✓ (Claude) |
| Inside AI.chat/2 opts | Adds guardrails: [...] to AI.chat. Touches existing code. | |

**User's choice:** You decide → Claude chose standalone

## Claude's Discretion

- Exact telemetry metadata shapes, from_config naming, preset jailbreak override behavior

## Deferred Ideas

None.
