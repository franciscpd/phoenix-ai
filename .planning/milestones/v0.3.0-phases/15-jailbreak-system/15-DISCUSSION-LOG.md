# Phase 15: Jailbreak System - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-04
**Phase:** 15-jailbreak-system
**Areas discussed:** Keyword patterns, Detect/2 return type, Score combination

---

## Keyword Patterns

| Option | Description | Selected |
|--------|-------------|----------|
| Follow PRD exactly | Use patterns and weights as defined in PRD | |
| PRD + case-insensitive | Same patterns but case-insensitive with word boundary (\b) matching | ✓ |
| You decide | Claude chooses | |

**User's choice:** PRD + case-insensitive
**Notes:** Reduces false negatives from casing variations and false positives from substring matches.

---

## Detect/2 Return Type

| Option | Description | Selected |
|--------|-------------|----------|
| PRD original (4-tuple) | {:ok, :safe} or {:ok, :detected, score, details} | |
| Struct result | {:safe, %DetectionResult{}} or {:detected, %DetectionResult{score, details}} | ✓ |
| :safe or {:detected, map} | Simplified tuple without struct | |

**User's choice:** Struct result (DetectionResult)
**Notes:** More type-safe and extensible than a 4-element tuple. DetectionResult carries score, details, and patterns.

---

## Score Combination

| Option | Description | Selected |
|--------|-------------|----------|
| Simple sum (PRD) | sum(matched_weights) — can exceed 1.0 | |
| Sum capped at 1.0 | min(1.0, sum(matched_weights)) — intuitive 0-to-1 scale | ✓ |
| You decide | Claude chooses | |

**User's choice:** Sum capped at 1.0
**Notes:** More intuitive as a 0-to-1 probability-like score.

---

## Claude's Discretion

- DetectionResult struct field defaults
- Encoding evasion pattern specifics
- Moduledoc content and examples
- Test fixture messages

## Deferred Ideas

None — discussion stayed within phase scope.
