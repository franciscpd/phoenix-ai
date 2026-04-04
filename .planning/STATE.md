---
gsd_state_version: 1.0
milestone: v0.3.0
milestone_name: Guardrails
status: planning
stopped_at: Phase 15 context gathered
last_updated: "2026-04-04T20:37:13.586Z"
last_activity: 2026-04-04 — Roadmap created for v0.3.0
progress:
  total_phases: 5
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-04)

**Core value:** Developers can build AI-powered agents with skills, sequential pipelines, and parallel execution using idiomatic Elixir/Phoenix patterns and BEAM concurrency primitives.
**Current focus:** Milestone v0.3.0 — Guardrails

## Current Position

Phase: 13 — Core Contracts (not started)
Plan: —
Status: Roadmap approved, ready to plan Phase 13
Last activity: 2026-04-04 — Roadmap created for v0.3.0

```
Progress: [░░░░░░░░░░] 0% (0/5 phases)
```

## Session Continuity

Last session: 2026-04-04T20:37:13.584Z
Stopped at: Phase 15 context gathered
Resume file: .planning/phases/15-jailbreak-system/15-CONTEXT.md
Next action: `/gsd:plan-phase 13`

## Accumulated Context

### Decisions

- v0.1.0: `PhoenixAI.Conversation` stub module is dead code (never integrated — tech debt)
- v0.2.0: Usage normalization is a library concern — consumers must not normalize raw provider maps themselves
- v0.2.0: `provider_specific` field preserves the raw map for consumers who need provider-specific fields not captured in the normalized struct
- v0.3.0: Guardrails PRD splits stateless policies (core) from stateful policies (phoenix_ai_store)
- v0.3.0: Pipeline executor must be a pure function in the caller's process — GenServer for pipeline is an explicit anti-pattern
- v0.3.0: `JailbreakDetector` behaviour decouples detection algorithm from `JailbreakDetection` policy — each independently testable with Mox
- v0.3.0: Policies return `{:halt, %PolicyViolation{}}` internally; executor maps to `{:error, %PolicyViolation{}}` at the boundary — struct type is the discriminator vs provider errors
- v0.3.0: No new runtime dependencies — `Enum.reduce_while/3`, `@behaviour`, `defstruct` cover the entire implementation; `nimble_options` and `telemetry` already in deps
- v0.3.0: Phase 5 (Agent Integration) flagged in research as the only phase touching existing production code — approach `Agent.handle_call/3` opts schema extension carefully

### Pending Todos

- Review `PhoenixAI.Agent` NimbleOptions schema before planning Phase 17 to confirm `:guardrails` opts slot in without breaking existing call sites

### Blockers/Concerns

None.
