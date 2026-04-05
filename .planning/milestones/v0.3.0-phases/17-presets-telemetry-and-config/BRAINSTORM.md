# Phase 17: Presets, Telemetry, and Config — Design Spec

**Date:** 2026-04-04
**Status:** Approved
**Approach:** Extend existing Pipeline module (A)

## Summary

Extend `PhoenixAI.Guardrails.Pipeline` with three developer experience features: named presets (`preset/1`), telemetry instrumentation (span for pipeline, execute per policy, jailbreak event), and NimbleOptions config validation (`from_config/1`). No new modules created — all additions go into the existing Pipeline module.

## Architecture

```
lib/phoenix_ai/guardrails/
  pipeline.ex    — Extended with preset/1, from_config/1, telemetry (this phase)
```

Modifications only — no new files in `lib/`. New test file for the new functionality.

## Module Specification

### Pipeline Extensions

#### 1. Presets (`preset/1`)

```elixir
alias PhoenixAI.Guardrails.Policies.{ContentFilter, JailbreakDetection, ToolPolicy}

@spec preset(:default | :strict | :permissive) :: [policy_entry()]
def preset(:default), do: [{JailbreakDetection, []}]
def preset(:strict), do: [{JailbreakDetection, []}, {ContentFilter, []}, {ToolPolicy, []}]
def preset(:permissive), do: [{JailbreakDetection, [threshold: 0.9]}]
```

**Design decisions:**
- Three function clauses, pure data return
- `:default` includes only JailbreakDetection (minimal safety)
- `:strict` includes all three policies (maximum protection)
- `:permissive` uses higher threshold (0.9) for reduced false positives
- Returns `[policy_entry()]` — same type as `run/2`'s first argument

#### 2. Telemetry

`run/2` gains telemetry instrumentation:

```elixir
def run([], %Request{} = request), do: {:ok, request}

def run(policies, %Request{} = request) when is_list(policies) do
  meta = %{policy_count: length(policies)}

  :telemetry.span([:phoenix_ai, :guardrails, :check], meta, fn ->
    result = execute_policies(policies, request)
    {result, meta}
  end)
end

defp execute_policies(policies, request) do
  Enum.reduce_while(policies, {:ok, request}, fn {module, opts}, {:ok, req} ->
    start_time = System.monotonic_time()
    policy_result = module.check(req, opts)
    duration = System.monotonic_time() - start_time

    case policy_result do
      {:ok, %Request{} = updated_req} ->
        emit_policy_event(module, :pass, duration)
        {:cont, {:ok, updated_req}}

      {:halt, %PolicyViolation{} = violation} ->
        emit_policy_event(module, :violation, duration)
        maybe_emit_jailbreak(module, violation)
        {:halt, {:error, violation}}
    end
  end)
end

defp emit_policy_event(module, result, duration) do
  :telemetry.execute(
    [:phoenix_ai, :guardrails, :policy, :stop],
    %{duration: duration},
    %{policy: module, result: result}
  )
end

defp maybe_emit_jailbreak(JailbreakDetection, %PolicyViolation{metadata: meta}) do
  :telemetry.execute(
    [:phoenix_ai, :guardrails, :jailbreak, :detected],
    %{},
    %{score: meta[:score], threshold: meta[:threshold], patterns: meta[:patterns]}
  )
end

defp maybe_emit_jailbreak(_module, _violation), do: :ok
```

**Telemetry events:**

| Event | Source | Metadata |
|-------|--------|----------|
| `[:phoenix_ai, :guardrails, :check, :start]` | span auto | `%{policy_count: N}` |
| `[:phoenix_ai, :guardrails, :check, :stop]` | span auto | `%{policy_count: N, duration: N}` |
| `[:phoenix_ai, :guardrails, :check, :exception]` | span auto | `%{policy_count: N, kind: K, reason: R, stacktrace: S}` |
| `[:phoenix_ai, :guardrails, :policy, :stop]` | execute | `%{policy: module, result: :pass \| :violation}` + `%{duration: N}` |
| `[:phoenix_ai, :guardrails, :jailbreak, :detected]` | execute | `%{score: F, threshold: F, patterns: [S]}` |

**Design decisions:**
- `:telemetry.span/3` for pipeline — auto-emits start/stop/exception
- Manual `:telemetry.execute/3` per policy with measured duration
- `maybe_emit_jailbreak/2` pattern matches on `JailbreakDetection` module atom — only fires for jailbreak violations
- Follows existing telemetry naming: `[:phoenix_ai, :domain, :action]`

#### 3. NimbleOptions Config (`from_config/1`)

```elixir
@guardrails_schema NimbleOptions.new!([
  policies: [type: {:list, :any}, doc: "Explicit policy list [{module, opts}]"],
  preset: [type: {:in, [:default, :strict, :permissive]}, doc: "Named preset"],
  jailbreak_threshold: [type: :float, default: 0.7, doc: "Jailbreak score threshold"],
  jailbreak_scope: [
    type: {:in, [:last_message, :all_user_messages]},
    default: :last_message,
    doc: "Jailbreak scan scope"
  ],
  jailbreak_detector: [
    type: :atom,
    default: PhoenixAI.Guardrails.JailbreakDetector.Default,
    doc: "Jailbreak detector module"
  ]
])

@spec from_config(keyword()) :: {:ok, [policy_entry()]} | {:error, NimbleOptions.ValidationError.t()}
def from_config(opts) do
  case NimbleOptions.validate(opts, @guardrails_schema) do
    {:ok, validated} -> {:ok, build_policies(validated)}
    {:error, _} = error -> error
  end
end
```

**`build_policies/1` logic:**
- If `policies` key present → use directly (ignoring preset)
- If `preset` key present → expand via `preset/1`, apply jailbreak_* overrides to JailbreakDetection opts
- If neither → return `[]`
- `policies` and `preset` are mutually exclusive — custom NimbleOptions validator

**Design decisions:**
- Standalone `from_config/1` — does NOT modify `AI.chat/2`
- Returns `{:ok, policies} | {:error, validation_error}` — standard Elixir error tuple
- Schema as module attribute `@guardrails_schema` — compiled once
- Jailbreak overrides: `jailbreak_threshold`, `jailbreak_scope`, `jailbreak_detector` are applied to the JailbreakDetection entry in the resolved policy list

## Testing Strategy

### Test Files

```
test/phoenix_ai/guardrails/pipeline_preset_test.exs
test/phoenix_ai/guardrails/pipeline_telemetry_test.exs
test/phoenix_ai/guardrails/pipeline_config_test.exs
```

Separate test files for each concern, all testing the same Pipeline module.

### Preset Tests

1. `preset(:default)` returns list with JailbreakDetection
2. `preset(:strict)` returns list with all 3 policies
3. `preset(:permissive)` returns list with JailbreakDetection and threshold 0.9
4. Preset output works with `Pipeline.run/2` (integration)

### Telemetry Tests

1. `run/2` emits `[:phoenix_ai, :guardrails, :check, :start]` and `:stop`
2. Per-policy `:stop` event emitted with policy module and result
3. Jailbreak `:detected` event emitted when JailbreakDetection halts
4. No jailbreak event when other policies halt
5. Exception event emitted when policy raises

### Config Tests

1. `from_config(preset: :default)` returns `{:ok, policies}`
2. `from_config(policies: [{...}])` returns policies as-is
3. `from_config([])` returns `{:ok, []}`
4. Invalid preset returns `{:error, %NimbleOptions.ValidationError{}}`
5. Invalid type returns validation error
6. Jailbreak overrides applied to preset
7. `policies` + `preset` together returns validation error

## Canonical References

- `lib/ai.ex:66` — `:telemetry.span` pattern
- `lib/phoenix_ai/pipeline.ex:96` — per-step telemetry pattern
- `lib/ai.ex:22-51` — NimbleOptions schema pattern
- `lib/phoenix_ai/guardrails/pipeline.ex` — existing Pipeline.run/2 to extend

---

*Phase: 17-presets-telemetry-and-config*
*Design approved: 2026-04-04*
