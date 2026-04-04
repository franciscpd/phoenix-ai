# Phase 14: Pipeline Executor — Design Spec

**Date:** 2026-04-04
**Status:** Approved
**Approach:** Direct reduce_while (A)

## Summary

Single module `PhoenixAI.Guardrails.Pipeline` with `run/2` that executes an ordered list of `{module, opts}` policy entries against a Request using `Enum.reduce_while/3`. Halts on first violation. Pure function, no process state.

## Architecture

```
lib/phoenix_ai/guardrails/
  pipeline.ex    — Pipeline.run/2 executor (this phase)
```

Dependencies: `Policy` behaviour, `Request` struct, `PolicyViolation` struct (all from Phase 13).

## Module Specification

### Pipeline (`PhoenixAI.Guardrails.Pipeline`)

```elixir
defmodule PhoenixAI.Guardrails.Pipeline do
  @moduledoc """
  Executes an ordered list of guardrail policies against a request.

  Policies run sequentially. Each receives the (possibly modified)
  request from the previous policy. The pipeline halts on the first
  `{:halt, %PolicyViolation{}}`.

  ## Example

      policies = [
        {MyJailbreakPolicy, [threshold: 0.7]},
        {MyContentFilter, [pre: &sanitize/1]}
      ]

      case Pipeline.run(policies, request) do
        {:ok, request} -> AI.chat(request.messages, opts)
        {:error, violation} -> handle_violation(violation)
      end
  """

  alias PhoenixAI.Guardrails.{Request, PolicyViolation}

  @type policy_entry :: {module(), keyword()}

  @spec run([policy_entry()], Request.t()) ::
          {:ok, Request.t()} | {:error, PolicyViolation.t()}
  def run([], request), do: {:ok, request}

  def run(policies, %Request{} = request) do
    Enum.reduce_while(policies, {:ok, request}, fn {module, opts}, {:ok, req} ->
      case module.check(req, opts) do
        {:ok, %Request{} = updated_req} ->
          {:cont, {:ok, updated_req}}

        {:halt, %PolicyViolation{} = violation} ->
          {:halt, {:error, violation}}
      end
    end)
  end
end
```

### Design Decisions

- **`run([], request)` clause:** Empty policies = everything passes. Returns `{:ok, request}` immediately.
- **Pattern match on args:** `%Request{} = request` guarantees type safety at the entry point.
- **Pattern match on returns:** `%Request{}` and `%PolicyViolation{}` on policy return values act as runtime guards — corrupted returns produce match errors instead of silent propagation.
- **Request mutation:** Policies can modify the request (e.g., sanitize messages, add assigns). The modified request propagates to the next policy via the accumulator.
- **No halt state update on request:** The halted request is not returned to the caller — only the `PolicyViolation` is. Updating `halted/violation` on a request that's never observed would be dead computation. If Agent integration (Phase 17) needs the halted request, the executor can be extended then.
- **API boundary mapping:** `{:halt, violation}` from `check/2` is mapped to `{:error, violation}` at the public boundary. Consumers use standard `{:ok, _} | {:error, _}` pattern matching.
- **No telemetry:** Telemetry events deferred to Phase 17.
- **No presets:** `run/2` accepts only `[{module, opts}]`. Preset resolution deferred to Phase 17.
- **Pure function:** Runs in the caller's process. No GenServer, no ETS, no shared state.

## Testing Strategy

### Test File

```
test/phoenix_ai/guardrails/pipeline_test.exs
```

### Approach

All tests use `Mox.expect/3` with `PhoenixAI.Guardrails.MockPolicy` — no concrete policies exist yet.

### Test Cases

1. **Empty policies list** — `run([], request)` returns `{:ok, request}` unchanged
2. **Single passing policy** — Mock returns `{:ok, request}`, pipeline returns `{:ok, request}`
3. **Single halting policy** — Mock returns `{:halt, violation}`, pipeline returns `{:error, violation}`
4. **Multiple policies, all pass** — 2 mocks pass sequentially, pipeline returns `{:ok, final_request}`
5. **Multiple policies, second halts** — First mock passes, second halts, third mock never called (verified via Mox expect count)
6. **Request modification propagates** — First mock adds to `assigns`, second mock receives modified request with the new assigns
7. **Violation contains policy module** — The returned `PolicyViolation` identifies which policy halted the pipeline via the `policy` field

### Mox Pattern

```elixir
setup :verify_on_exit!

# Define N expects — Mox enforces they're called exactly N times
MockPolicy
|> expect(:check, fn req, _opts -> {:ok, req} end)
|> expect(:check, fn _req, _opts ->
  {:halt, %PolicyViolation{policy: MockPolicy, reason: "Blocked"}}
end)

# Third policy never called — Mox.verify! confirms only 2 calls happened
```

## Approach Trade-offs (Considered)

| Approach | Description | Verdict |
|----------|-------------|---------|
| **A: Direct reduce_while** | **~15 lines, mirrors existing Pipeline pattern** | **Selected — simple, tested, idiomatic** |
| B: Plug-style Builder | Macro-based declarative API | Over-engineered — presets cover composition |
| C: GenServer pipeline | Process-based pipeline | Anti-pattern — violates "pure function" decision |

## Downstream Dependencies

- **Phase 15-16 (Concrete Policies)** — their policy modules become `{module, opts}` entries
- **Phase 17 (Presets)** — `Pipeline.preset(:default)` returns `[{module, opts}]` for `run/2`
- **Phase 17 (Telemetry)** — telemetry spans wrap `run/2` and per-policy `check/2` calls

## Canonical References

- `lib/phoenix_ai/pipeline.ex:86-107` — Existing `reduce_while` pattern to mirror
- `lib/phoenix_ai/guardrails/policy.ex` — Policy behaviour (`check/2` contract)
- `lib/phoenix_ai/guardrails/request.ex` — Request struct
- `lib/phoenix_ai/guardrails/policy_violation.ex` — PolicyViolation struct
- `test/test_helper.exs` — MockPolicy Mox definition

---

*Phase: 14-pipeline-executor*
*Design approved: 2026-04-04*
