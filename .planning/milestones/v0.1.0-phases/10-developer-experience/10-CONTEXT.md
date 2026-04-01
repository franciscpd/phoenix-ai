# Phase 10: Developer Experience - Context

**Gathered:** 2026-03-31
**Status:** Ready for planning

<domain>
## Phase Boundary

The library becomes testable without network calls, instrumented with telemetry, validated with NimbleOptions schemas on all public APIs, documented with ExDoc guides and cookbook, and published to Hex. This phase adds no new runtime capabilities — it wraps the existing functionality with developer-facing quality: testing ergonomics, observability, option validation, documentation, and distribution.

**Not in scope:** New providers, new orchestration patterns, persistence, LiveView helpers, embedding/vector search (all v2 or out of scope per REQUIREMENTS.md).

</domain>

<decisions>
## Implementation Decisions

### TestProvider (DX-01)
- **D-01:** Hybrid approach — queue FIFO as default + function handler override. `TestProvider.set_responses([r1, r2])` for simple cases (each `chat/2` call consumes the next response in order). `TestProvider.set_handler(fn messages, opts -> {:ok, response} end)` for custom logic when the test needs to inspect input or branch behavior.
- **D-02:** TestProvider implements the `PhoenixAI.Provider` behaviour — it is a real provider adapter, not a mock. This means it can be used via `AI.chat(messages, provider: :test)` with the standard dispatch path.
- **D-03:** State is process-local (Agent or ETS per-test). No shared global state that would break async ExUnit tests. Each test owns its own TestProvider state.

### Telemetry (DX-02)
- **D-04:** Span-based for chat and stream operations — `:telemetry.span/3` measures duration automatically. Events: `[:phoenix_ai, :chat, :start]`, `[:phoenix_ai, :chat, :stop]`, `[:phoenix_ai, :chat, :exception]`. Metadata includes: `provider`, `model`, `token_usage` (on stop).
- **D-05:** Discrete execute events for tool calls and orchestration steps — `[:phoenix_ai, :tool_call, :start/:stop]`, `[:phoenix_ai, :pipeline, :step]`, `[:phoenix_ai, :team, :run]`. These fire via `:telemetry.execute/3` at specific points.
- **D-06:** Naming convention follows the Elixir ecosystem standard: `[:app_name, :resource, :action]`. Consistent with how Phoenix, Ecto, and Oban name their events.

### NimbleOptions (DX-03)
- **D-07:** Validation on ALL public API entry points: `AI.chat/2`, `AI.stream/3`, `Agent.start_link/1`, `Pipeline.run/2`, `Team.run/3`. Every public function that accepts options validates them before proceeding.
- **D-08:** Schemas are co-located with their functions — each module defines its own `@opts_schema NimbleOptions.new!(...)` at the top. No central schema registry. This keeps schemas discoverable and maintainable next to the code they validate.
- **D-09:** Invalid options return `{:error, %NimbleOptions.ValidationError{}}` with human-readable messages — consistent with the library's `{:ok, _}/{:error, _}` pattern. Never raises on bad options (CORE-05 compliance).

### ExDoc & Hex Publish (DX-04, DX-05)
- **D-10:** Four main guides: Getting Started, Provider Setup, Agent & Tools, Pipeline & Team. Each guide is a standalone `.md` file in a `guides/` directory, referenced in `mix.exs` docs config.
- **D-11:** Cookbook section with practical recipes: RAG pattern using Pipeline, multi-agent workflow using Team, streaming to a Phoenix LiveView process, custom tool creation. Recipes show real-world composition of library primitives.
- **D-12:** All public modules get complete `@moduledoc` with usage examples. All public functions get `@doc` with typespecs and examples.
- **D-13:** Hex publish with `~> major.minor` dependency pins (already in place in mix.exs). Package metadata already configured (`package/0`, `docs/0` in mix.exs). Version is `0.1.0` for initial release.

### Claude's Discretion
- TestProvider internal implementation (Agent vs ETS for state storage)
- Exact telemetry metadata keys beyond provider/model/token_usage
- Whether NimbleOptions schemas use `@opts_schema` module attribute or inline `NimbleOptions.validate!/2`
- ExDoc theme and styling choices
- Cookbook recipe ordering and depth
- Whether to add `@moduledoc` to internal/private modules
- Hex publish checklist details (license file, .hex metadata)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements
- `.planning/REQUIREMENTS.md` — DX-01 through DX-05: all Phase 10 requirements with acceptance criteria

### Prior Phase Context
- `.planning/phases/01-core-foundation/01-CONTEXT.md` — D-01: package name `phoenix_ai`, D-02: `AI` as main module, CORE-05: ok/error tuples
- `.planning/phases/08-pipeline-orchestration/08-CONTEXT.md` — Pipeline DSL pattern, `Pipeline.run/2` API
- `.planning/phases/09-team-orchestration/09-CONTEXT.md` — Team DSL pattern, `Team.run/3` API

### Existing Code
- `lib/phoenix_ai/config.ex` — Current config resolution (call-site > app env > env vars > defaults). NimbleOptions schemas will wrap this.
- `lib/phoenix_ai/provider.ex` — Provider behaviour that TestProvider must implement
- `mix.exs` — Already has `nimble_options`, `telemetry`, `ex_doc` deps and `package/0`/`docs/0` config

### Ecosystem Patterns
- NimbleOptions docs (hexdocs.pm) — Schema definition and validation patterns
- `:telemetry` docs — Span and execute usage, naming conventions
- ExDoc docs — Guide configuration, extras, groups

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `PhoenixAI.Provider` behaviour — TestProvider implements this directly
- `PhoenixAI.Response` struct — TestProvider returns these
- `PhoenixAI.Config` — Config resolution cascade to integrate NimbleOptions with
- `mix.exs` `package/0` and `docs/0` — Already configured, needs expansion for guides

### Established Patterns
- `{:ok, result} | {:error, reason}` tuples on all public functions (CORE-05)
- Provider behaviour: `chat/2`, `stream/3`, `format_tools/1`, `parse_response/1` callbacks
- DSL via `use Module` + macros + `@before_compile` (Pipeline, Team)
- Pure functional modules for orchestration (ToolLoop, Pipeline, Team)
- `test/support/` directory for test helpers (tools, fixtures, schemas already present)

### Integration Points
- `lib/phoenix_ai/providers/test_provider.ex` — New provider adapter
- `lib/phoenix_ai/` — Each existing module gets NimbleOptions schema added
- `lib/phoenix_ai/` — Each chat/stream/tool path gets telemetry instrumentation
- `guides/` — New directory for ExDoc guides
- `test/support/` — TestProvider helpers go here alongside existing fixtures

</code_context>

<specifics>
## Specific Ideas

- TestProvider as hybrid (queue + handler) covers both simple assertion tests and complex behavior-driven tests without forcing a choice
- Telemetry spans for chat/stream give duration for free; discrete events for tool_call/pipeline_step/team_run give granular observability for debugging agent workflows
- NimbleOptions co-located with each module keeps schemas discoverable — `AI.chat/2` schema lives in `AI`, not in a central registry
- Cookbook recipes demonstrate real composition: Pipeline step that calls Team (parallel inside sequential), streaming to LiveView PID, RAG pattern — these are the patterns users will actually build
- `provider: :test` in the standard dispatch path means TestProvider is a first-class citizen, not a hack

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 10-developer-experience*
*Context gathered: 2026-03-31*
