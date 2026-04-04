# Phase 13: Core Contracts - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-04
**Phase:** 13-core-contracts
**Areas discussed:** Policy return type, Request.assigns, Request.tool_calls type, Module namespace

---

## Policy Return Type

| Option | Description | Selected |
|--------|-------------|----------|
| `{:ok, req} \| {:error, viol}` | Simpler. Follows original PRD. Consumers already know `{:ok, _} \| {:error, _}` pattern | |
| `{:ok, req} \| {:halt, viol}` | Differentiates policy halt from technical errors. More explicit. Executor maps `{:halt, _}` to `{:error, _}` at boundary | ✓ |

**User's choice:** `{:ok, req} | {:halt, viol}`
**Notes:** Chosen because a policy rejection is not an error — it's the system working as expected. `:halt` atom communicates this clearly, similar to `Plug.Conn.halt/1`.

---

## Request.assigns

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, use assigns | Separate field for inter-policy communication (Plug pattern). metadata for user data, assigns for pipeline | ✓ |
| No, metadata is enough | Keep simple. metadata: %{} serves both user and inter-policy. Fewer struct fields | |
| You decide | Let Claude choose based on what makes most sense | |

**User's choice:** Yes, use assigns
**Notes:** Separates pipeline-internal state (assigns) from consumer-provided context (metadata).

---

## Request.tool_calls Type

| Option | Description | Selected |
|--------|-------------|----------|
| Reuse ToolCall.t() | Consistent with Message.t(). ToolPolicy can inspect .name directly. Strong typing | ✓ |
| Keep [map()] | More flexible, no coupling with ToolCall. But loses typing and consistency | |

**User's choice:** Reuse ToolCall.t()
**Notes:** Maintains consistency with existing codebase. ToolCall.t() already has the fields ToolPolicy needs (id, name, arguments).

---

## Module Namespace

| Option | Description | Selected |
|--------|-------------|----------|
| Follow the PRD | PhoenixAI.Guardrails.Policy, .Request, .PolicyViolation, .Pipeline, .Policies.JailbreakDetection etc. | ✓ |
| Flat in Guardrails | Everything directly in PhoenixAI.Guardrails.* without policies/ subfolder | |
| You decide | Claude chooses based on existing codebase conventions | |

**User's choice:** Follow the PRD
**Notes:** The PRD structure groups concrete policies under Policies.* namespace while keeping contracts (Policy, Request, PolicyViolation, Pipeline) at the Guardrails.* level.

---

## Claude's Discretion

- Typespec conventions, field defaults, moduledoc depth — follow existing codebase patterns

## Deferred Ideas

None — discussion stayed within phase scope.
