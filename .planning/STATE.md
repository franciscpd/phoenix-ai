---
gsd_state_version: 1.0
milestone: v0.3.1
milestone_name: Provider Field
status: active
stopped_at: null
last_updated: "2026-04-05T02:30:00.000Z"
last_activity: 2026-04-05 — Milestone v0.3.1 started
progress:
  total_phases: 0
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-05)

**Core value:** Developers can build AI-powered agents with skills, sequential pipelines, and parallel execution using idiomatic Elixir/Phoenix patterns and BEAM concurrency primitives.
**Current focus:** Milestone v0.3.1 — Provider Field

## Current Position

Phase: Not started (defining requirements)
Plan: —
Status: Defining requirements
Last activity: 2026-04-05 — Milestone v0.3.1 started

## Session Continuity

Last session: 2026-04-05T02:30:00.000Z
Stopped at: null
Resume file: —
Next action: Define requirements

## Accumulated Context

### Decisions

- v0.1.0: `PhoenixAI.Conversation` stub module is dead code (never integrated — tech debt)
- v0.2.0: Usage normalization is a library concern — consumers must not normalize raw provider maps themselves
- v0.2.0: `provider_specific` field preserves the raw map for consumers who need provider-specific fields not captured in the normalized struct
- v0.3.0: Guardrails PRD splits stateless policies (core) from stateful policies (phoenix_ai_store)
- v0.3.0: Pipeline executor must be a pure function in the caller's process — GenServer for pipeline is an explicit anti-pattern
- v0.3.0: `JailbreakDetector` behaviour decouples detection algorithm from `JailbreakDetection` policy — each independently testable with Mox
- v0.3.0: Policies return `{:halt, %PolicyViolation{}}` internally; executor maps to `{:error, %PolicyViolation{}}` at the boundary — struct type is the discriminator vs provider errors

### Pending Todos

None.

### Blockers/Concerns

None.
