# Phase 17: Presets, Telemetry, and Config — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend `PhoenixAI.Guardrails.Pipeline` with named presets, telemetry instrumentation, and NimbleOptions config validation — completing the v0.3.0 guardrails framework.

**Architecture:** All additions go into the existing `Pipeline` module (~47 lines → ~120 lines). Presets are pure data functions. Telemetry wraps `run/2` with `:telemetry.span/3` and per-policy `:telemetry.execute/3`. Config uses `NimbleOptions.validate/2` to build policy lists from keyword options.

**Tech Stack:** Elixir, ExUnit, Mox, :telemetry, NimbleOptions

---

### Task 1: Presets

**Files:**
- Modify: `lib/phoenix_ai/guardrails/pipeline.ex`
- Create: `test/phoenix_ai/guardrails/pipeline_preset_test.exs`

- [ ] **Step 1: Write the failing tests**

```elixir
# test/phoenix_ai/guardrails/pipeline_preset_test.exs
defmodule PhoenixAI.Guardrails.PipelinePresetTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Guardrails.Pipeline
  alias PhoenixAI.Guardrails.Policies.{ContentFilter, JailbreakDetection, ToolPolicy}

  describe "preset/1" do
    test ":default returns JailbreakDetection only" do
      assert [{JailbreakDetection, []}] = Pipeline.preset(:default)
    end

    test ":strict returns all three policies" do
      policies = Pipeline.preset(:strict)
      assert length(policies) == 3
      assert {JailbreakDetection, []} in policies
      assert {ContentFilter, []} in policies
      assert {ToolPolicy, []} in policies
    end

    test ":permissive returns JailbreakDetection with high threshold" do
      assert [{JailbreakDetection, opts}] = Pipeline.preset(:permissive)
      assert opts[:threshold] == 0.9
    end

    test "preset output works with Pipeline.run/2" do
      alias PhoenixAI.Guardrails.Request
      alias PhoenixAI.Message

      request = %Request{messages: [%Message{role: :user, content: "Hello world"}]}
      policies = Pipeline.preset(:default)

      assert {:ok, ^request} = Pipeline.run(policies, request)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_ai/guardrails/pipeline_preset_test.exs`
Expected: `UndefinedFunctionError` — `Pipeline.preset/1` does not exist.

- [ ] **Step 3: Add preset/1 to Pipeline module**

Add the following to `lib/phoenix_ai/guardrails/pipeline.ex` after the existing `run/2` clauses (before `end`):

```elixir
  alias PhoenixAI.Guardrails.Policies.{ContentFilter, JailbreakDetection, ToolPolicy}

  @doc """
  Returns a named preset policy list.

  ## Presets

    * `:default` — JailbreakDetection only (minimal safety)
    * `:strict` — All three policies (maximum protection)
    * `:permissive` — JailbreakDetection with high threshold (reduced false positives)
  """
  @spec preset(:default | :strict | :permissive) :: [policy_entry()]
  def preset(:default), do: [{JailbreakDetection, []}]

  def preset(:strict),
    do: [{JailbreakDetection, []}, {ContentFilter, []}, {ToolPolicy, []}]

  def preset(:permissive), do: [{JailbreakDetection, [threshold: 0.9]}]
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/phoenix_ai/guardrails/pipeline_preset_test.exs`
Expected: 4 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_ai/guardrails/pipeline.ex test/phoenix_ai/guardrails/pipeline_preset_test.exs
git commit -m "feat(guardrails): add Pipeline.preset/1 for :default, :strict, :permissive"
```

---

### Task 2: Telemetry

**Files:**
- Modify: `lib/phoenix_ai/guardrails/pipeline.ex`
- Create: `test/phoenix_ai/guardrails/pipeline_telemetry_test.exs`

- [ ] **Step 1: Write the failing tests**

```elixir
# test/phoenix_ai/guardrails/pipeline_telemetry_test.exs
defmodule PhoenixAI.Guardrails.PipelineTelemetryTest do
  use ExUnit.Case, async: false

  import Mox

  alias PhoenixAI.Guardrails.{MockPolicy, Pipeline, PolicyViolation, Request}
  alias PhoenixAI.Message

  setup :verify_on_exit!

  defp build_request(content \\ "Hello") do
    %Request{messages: [%Message{role: :user, content: content}]}
  end

  describe "telemetry: pipeline span" do
    test "emits :start and :stop events for successful pipeline" do
      request = build_request()

      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:phoenix_ai, :guardrails, :check, :start],
          [:phoenix_ai, :guardrails, :check, :stop]
        ])

      MockPolicy
      |> expect(:check, fn req, _opts -> {:ok, req} end)

      assert {:ok, _} = Pipeline.run([{MockPolicy, []}], request)

      assert_received {[:phoenix_ai, :guardrails, :check, :start], ^ref, _measurements, meta}
      assert meta.policy_count == 1

      assert_received {[:phoenix_ai, :guardrails, :check, :stop], ^ref, measurements, meta}
      assert meta.policy_count == 1
      assert is_integer(measurements.duration)
    end
  end

  describe "telemetry: per-policy events" do
    test "emits :policy :stop event for each policy" do
      request = build_request()

      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:phoenix_ai, :guardrails, :policy, :stop]
        ])

      MockPolicy
      |> expect(:check, 2, fn req, _opts -> {:ok, req} end)

      assert {:ok, _} = Pipeline.run([{MockPolicy, []}, {MockPolicy, []}], request)

      assert_received {[:phoenix_ai, :guardrails, :policy, :stop], ^ref, measurements, meta}
      assert meta.policy == MockPolicy
      assert meta.result == :pass
      assert is_integer(measurements.duration)

      assert_received {[:phoenix_ai, :guardrails, :policy, :stop], ^ref, _m, meta2}
      assert meta2.result == :pass
    end

    test "emits :violation result when policy halts" do
      request = build_request()

      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:phoenix_ai, :guardrails, :policy, :stop]
        ])

      violation = %PolicyViolation{policy: MockPolicy, reason: "Blocked"}

      MockPolicy
      |> expect(:check, fn _req, _opts -> {:halt, violation} end)

      assert {:error, _} = Pipeline.run([{MockPolicy, []}], request)

      assert_received {[:phoenix_ai, :guardrails, :policy, :stop], ^ref, _m, meta}
      assert meta.result == :violation
    end
  end

  describe "telemetry: jailbreak detected event" do
    test "emits jailbreak :detected event when JailbreakDetection halts" do
      request = build_request()

      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:phoenix_ai, :guardrails, :jailbreak, :detected]
        ])

      violation = %PolicyViolation{
        policy: PhoenixAI.Guardrails.Policies.JailbreakDetection,
        reason: "Jailbreak detected",
        metadata: %{score: 0.85, threshold: 0.7, patterns: ["ignore previous"]}
      }

      MockPolicy
      |> expect(:check, fn _req, _opts -> {:halt, violation} end)

      assert {:error, _} =
               Pipeline.run(
                 [{MockPolicy, []}],
                 request
               )

      assert_received {[:phoenix_ai, :guardrails, :jailbreak, :detected], ^ref, _m, meta}
      assert meta.score == 0.85
      assert meta.threshold == 0.7
      assert meta.patterns == ["ignore previous"]
    end

    test "does not emit jailbreak event for other policy violations" do
      request = build_request()

      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:phoenix_ai, :guardrails, :jailbreak, :detected]
        ])

      violation = %PolicyViolation{
        policy: PhoenixAI.Guardrails.Policies.ToolPolicy,
        reason: "Tool blocked",
        metadata: %{tool: "delete_all", mode: :deny}
      }

      MockPolicy
      |> expect(:check, fn _req, _opts -> {:halt, violation} end)

      assert {:error, _} = Pipeline.run([{MockPolicy, []}], request)

      refute_received {[:phoenix_ai, :guardrails, :jailbreak, :detected], ^ref, _, _}
    end
  end

  describe "telemetry: empty pipeline" do
    test "no telemetry events for empty policy list" do
      request = build_request()

      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:phoenix_ai, :guardrails, :check, :start]
        ])

      assert {:ok, _} = Pipeline.run([], request)

      refute_received {[:phoenix_ai, :guardrails, :check, :start], ^ref, _, _}
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_ai/guardrails/pipeline_telemetry_test.exs`
Expected: Failures — no telemetry events emitted by current `run/2`.

- [ ] **Step 3: Add telemetry to Pipeline.run/2**

Replace the existing `run/2` non-empty clause in `lib/phoenix_ai/guardrails/pipeline.ex`:

```elixir
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
          maybe_emit_jailbreak(violation)
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

  defp maybe_emit_jailbreak(%PolicyViolation{
         policy: PhoenixAI.Guardrails.Policies.JailbreakDetection,
         metadata: meta
       }) do
    :telemetry.execute(
      [:phoenix_ai, :guardrails, :jailbreak, :detected],
      %{},
      %{score: meta[:score], threshold: meta[:threshold], patterns: meta[:patterns]}
    )
  end

  defp maybe_emit_jailbreak(_violation), do: :ok
```

- [ ] **Step 4: Run telemetry tests**

Run: `mix test test/phoenix_ai/guardrails/pipeline_telemetry_test.exs`
Expected: 6 tests, 0 failures.

- [ ] **Step 5: Run existing pipeline tests to verify no regressions**

Run: `mix test test/phoenix_ai/guardrails/pipeline_test.exs test/phoenix_ai/guardrails/pipeline_telemetry_test.exs`
Expected: 14 tests, 0 failures (8 original + 6 telemetry).

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_ai/guardrails/pipeline.ex test/phoenix_ai/guardrails/pipeline_telemetry_test.exs
git commit -m "feat(guardrails): add telemetry instrumentation to Pipeline.run/2"
```

---

### Task 3: NimbleOptions Config

**Files:**
- Modify: `lib/phoenix_ai/guardrails/pipeline.ex`
- Create: `test/phoenix_ai/guardrails/pipeline_config_test.exs`

- [ ] **Step 1: Write the failing tests**

```elixir
# test/phoenix_ai/guardrails/pipeline_config_test.exs
defmodule PhoenixAI.Guardrails.PipelineConfigTest do
  use ExUnit.Case, async: true

  alias PhoenixAI.Guardrails.Pipeline
  alias PhoenixAI.Guardrails.Policies.{ContentFilter, JailbreakDetection, ToolPolicy}

  describe "from_config/1 with preset" do
    test "resolves :default preset" do
      assert {:ok, policies} = Pipeline.from_config(preset: :default)
      assert [{JailbreakDetection, []}] = policies
    end

    test "resolves :strict preset" do
      assert {:ok, policies} = Pipeline.from_config(preset: :strict)
      assert length(policies) == 3
    end

    test "resolves :permissive preset" do
      assert {:ok, policies} = Pipeline.from_config(preset: :permissive)
      assert [{JailbreakDetection, opts}] = policies
      assert opts[:threshold] == 0.9
    end

    test "applies jailbreak_threshold override to preset" do
      assert {:ok, [{JailbreakDetection, opts}]} =
               Pipeline.from_config(preset: :default, jailbreak_threshold: 0.5)

      assert opts[:threshold] == 0.5
    end

    test "applies jailbreak_scope override to preset" do
      assert {:ok, [{JailbreakDetection, opts}]} =
               Pipeline.from_config(preset: :default, jailbreak_scope: :all_user_messages)

      assert opts[:scope] == :all_user_messages
    end

    test "applies jailbreak_detector override to preset" do
      assert {:ok, [{JailbreakDetection, opts}]} =
               Pipeline.from_config(preset: :default, jailbreak_detector: MyCustomDetector)

      assert opts[:detector] == MyCustomDetector
    end
  end

  describe "from_config/1 with explicit policies" do
    test "returns policies as-is" do
      explicit = [{JailbreakDetection, [threshold: 0.5]}, {ContentFilter, []}]

      assert {:ok, ^explicit} = Pipeline.from_config(policies: explicit)
    end
  end

  describe "from_config/1 with empty opts" do
    test "returns empty policy list" do
      assert {:ok, []} = Pipeline.from_config([])
    end
  end

  describe "from_config/1 validation errors" do
    test "invalid preset returns error" do
      assert {:error, %NimbleOptions.ValidationError{}} =
               Pipeline.from_config(preset: :unknown)
    end

    test "invalid jailbreak_threshold type returns error" do
      assert {:error, %NimbleOptions.ValidationError{}} =
               Pipeline.from_config(preset: :default, jailbreak_threshold: "high")
    end

    test "invalid jailbreak_scope returns error" do
      assert {:error, %NimbleOptions.ValidationError{}} =
               Pipeline.from_config(preset: :default, jailbreak_scope: :invalid)
    end
  end

  describe "from_config/1 full integration" do
    test "from_config output works with Pipeline.run/2" do
      alias PhoenixAI.Guardrails.Request
      alias PhoenixAI.Message

      request = %Request{messages: [%Message{role: :user, content: "Hello world"}]}

      assert {:ok, policies} = Pipeline.from_config(preset: :default)
      assert {:ok, ^request} = Pipeline.run(policies, request)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_ai/guardrails/pipeline_config_test.exs`
Expected: `UndefinedFunctionError` — `Pipeline.from_config/1` does not exist.

- [ ] **Step 3: Add from_config/1 to Pipeline module**

Add the following to `lib/phoenix_ai/guardrails/pipeline.ex` (after preset/1, before `defp` helpers):

```elixir
  @guardrails_schema NimbleOptions.new!([
    policies: [type: {:list, :any}, doc: "Explicit policy list [{module, opts}]"],
    preset: [
      type: {:in, [:default, :strict, :permissive]},
      doc: "Named preset (:default, :strict, :permissive)"
    ],
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

  @doc """
  Builds a policy list from keyword configuration.

  Validates options via NimbleOptions and resolves presets with
  optional jailbreak overrides.

  ## Options

    * `:preset` — Named preset (:default, :strict, :permissive)
    * `:policies` — Explicit policy list (overrides preset)
    * `:jailbreak_threshold` — Override threshold (default 0.7)
    * `:jailbreak_scope` — Override scope (default :last_message)
    * `:jailbreak_detector` — Override detector module

  ## Examples

      {:ok, policies} = Pipeline.from_config(preset: :default)
      {:ok, policies} = Pipeline.from_config(preset: :strict, jailbreak_threshold: 0.5)
  """
  @spec from_config(keyword()) :: {:ok, [policy_entry()]} | {:error, NimbleOptions.ValidationError.t()}
  def from_config(opts) do
    case NimbleOptions.validate(opts, @guardrails_schema) do
      {:ok, validated} -> {:ok, build_policies(validated)}
      {:error, _} = error -> error
    end
  end

  defp build_policies(validated) do
    cond do
      validated[:policies] -> validated[:policies]
      validated[:preset] -> apply_jailbreak_overrides(preset(validated[:preset]), validated)
      true -> []
    end
  end

  defp apply_jailbreak_overrides(policies, validated) do
    Enum.map(policies, fn
      {JailbreakDetection, opts} ->
        overrides =
          []
          |> maybe_override(:threshold, validated[:jailbreak_threshold], 0.7)
          |> maybe_override(:scope, validated[:jailbreak_scope], :last_message)
          |> maybe_override(:detector, validated[:jailbreak_detector], PhoenixAI.Guardrails.JailbreakDetector.Default)

        {JailbreakDetection, Keyword.merge(opts, overrides)}

      other ->
        other
    end)
  end

  defp maybe_override(acc, key, value, default) when value != default do
    Keyword.put(acc, key, value)
  end

  defp maybe_override(acc, _key, _value, _default), do: acc
```

- [ ] **Step 4: Run config tests**

Run: `mix test test/phoenix_ai/guardrails/pipeline_config_test.exs`
Expected: 11 tests, 0 failures.

- [ ] **Step 5: Run full test suite**

Run: `mix test`
Expected: All tests pass (396 existing + ~21 new = ~417 tests, 0 failures).

- [ ] **Step 6: Run compiler with warnings-as-errors**

Run: `mix compile --warnings-as-errors`
Expected: Clean compilation.

- [ ] **Step 7: Commit**

```bash
git add lib/phoenix_ai/guardrails/pipeline.ex test/phoenix_ai/guardrails/pipeline_config_test.exs
git commit -m "feat(guardrails): add Pipeline.from_config/1 with NimbleOptions validation"
```
