# Roadmap: PhoenixAI

## Overview

PhoenixAI is built from the ground up in dependency order: canonical data model and provider behaviour contract first (Phase 1), then the remaining provider adapters (Phase 2), then tool calling with per-provider injection semantics (Phase 3), then the Agent GenServer that orchestrates the completion loop (Phase 4), then structured output validation (Phase 5), then the Finch-based SSE streaming transport (Phase 6), then the combined streaming-plus-tools integration that must be tested as a unit (Phase 7), then sequential pipeline orchestration (Phase 8), then parallel team execution (Phase 9), and finally the developer-experience layer — test sandbox, telemetry, NimbleOptions schemas, and Hex publication (Phase 10). Each phase delivers a coherent, independently-testable capability that unblocks the next.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Core Foundation** - Data model structs, Provider behaviour, HTTP transport, OpenAI adapter, call-site config, child_spec
- [ ] **Phase 2: Remaining Providers** - Anthropic + OpenRouter adapters, PhoenixAI.chat/2 provider dispatch
- [ ] **Phase 3: Tool Calling** - Tool behaviour, per-provider tool result injection, agent tool dispatch loop
- [ ] **Phase 4: Agent GenServer** - Completion-tool-call loop GenServer, DynamicSupervisor integration
- [ ] **Phase 5: Structured Output** - JSON schema definition, provider-side params, response validation
- [ ] **Phase 6: Streaming Transport** - Finch SSE layer, stateful buffer parser, provider parse_chunk/1 callbacks
- [ ] **Phase 7: Streaming + Tools Integration** - Combined streaming-tool-calling scenario, callback/PID chunk delivery
- [ ] **Phase 8: Pipeline Orchestration** - Sequential railway with ok/error halting
- [ ] **Phase 9: Team Orchestration** - Parallel Task.async_stream execution, max_concurrency, merge function
- [ ] **Phase 10: Developer Experience** - TestProvider sandbox, telemetry events, NimbleOptions schemas, ExDoc, Hex publish

## Phase Details

### Phase 1: Core Foundation
**Goal**: The library's structural skeleton exists — canonical data model, provider behaviour contract, HTTP transport, a working OpenAI adapter, call-site config, and no auto-starting processes
**Depends on**: Nothing (first phase)
**Requirements**: CORE-01, CORE-02, CORE-03, CORE-04, CORE-05, CORE-06, PROV-01
**Success Criteria** (what must be TRUE):
  1. A consumer can call `PhoenixAI.Providers.OpenAI.chat/2` with a list of Message structs and receive `{:ok, %Response{}}` or `{:error, reason}`
  2. All public functions return `{:ok, result}` or `{:error, reason}` — no bare raises
  3. API key and model can be passed at call-site and override Application env defaults
  4. Adding `PhoenixAI.child_spec([])` to a supervision tree starts only what was explicitly requested — no phantom processes
  5. `mix deps.get && mix test` passes on a fresh clone with only `req`, `jason`, `nimble_options`, `telemetry` as runtime deps
**Plans**: TBD

### Phase 2: Remaining Providers
**Goal**: All three v1 providers are available through a unified dispatch function, with provider-specific options passthrough
**Depends on**: Phase 1
**Requirements**: PROV-02, PROV-03, PROV-05, PROV-06
**Success Criteria** (what must be TRUE):
  1. `PhoenixAI.chat(messages, provider: :anthropic, model: "claude-opus-4-5")` returns `{:ok, %Response{}}`
  2. `PhoenixAI.chat(messages, provider: :openrouter, model: "...")` returns `{:ok, %Response{}}`
  3. `PhoenixAI.chat/2` resolves the correct adapter from the `provider:` option without caller knowing adapter module names
  4. Provider-specific parameters pass through untouched via `provider_options: %{...}` and reach the HTTP request
  5. An unknown provider atom returns `{:error, {:unknown_provider, atom}}` not a crash
**Plans**: TBD

### Phase 3: Tool Calling
**Goal**: Tools are callable modules, tool result injection is handled per-provider, and the round-trip works correctly for both OpenAI and Anthropic wire formats
**Depends on**: Phase 2
**Requirements**: TOOL-01, TOOL-02, TOOL-03, TOOL-04, TOOL-05, PROV-04
**Success Criteria** (what must be TRUE):
  1. A module implementing `PhoenixAI.Tool` callbacks can be passed to a provider and its schema is serialized to the correct provider format
  2. When the OpenAI adapter receives a tool call response, it injects `role: "tool"` messages with matching `tool_call_id` — not shared pipeline code
  3. When the Anthropic adapter receives a tool call response, it injects `role: "user"` messages with `type: "tool_result"` content blocks — not shared pipeline code
  4. The automatic tool loop (call provider → detect tool calls → execute tools → re-call provider → until stop) completes and returns the final response
  5. Tool modules contain no OTP — they are plain modules with zero GenServer/process involvement
**Plans**: TBD

### Phase 4: Agent GenServer
**Goal**: A stateful GenServer owns one conversation's state and runs the completion-tool-call loop; it is supervisable without being auto-started
**Depends on**: Phase 3
**Requirements**: AGENT-01, AGENT-02, AGENT-03, AGENT-04, AGENT-05
**Success Criteria** (what must be TRUE):
  1. `PhoenixAI.Agent.start_link(provider: ..., model: ..., system: ..., tools: [...])` starts a GenServer that accepts prompts
  2. `PhoenixAI.Agent.prompt(pid, "text")` blocks until the full completion-tool-call loop finishes and returns `{:ok, %Response{}}`
  3. Crashing one agent process (via `Process.exit(pid, :kill)`) does not affect any other running agent process
  4. The agent can be started under a DynamicSupervisor using its `child_spec/1` without any library-level supervisor auto-starting
  5. Conversation history accumulates correctly across multiple `prompt/2` calls within the same agent process
**Plans**: TBD

### Phase 5: Structured Output
**Goal**: JSON schemas can be declared as plain maps, providers receive the correct structured output parameters, and responses are validated before being returned
**Depends on**: Phase 4
**Requirements**: SCHEMA-01, SCHEMA-02, SCHEMA-03, SCHEMA-04
**Success Criteria** (what must be TRUE):
  1. A schema defined as a plain Elixir map (no Ecto dependency required) can be passed to `PhoenixAI.chat/2` and the provider receives well-formed structured output parameters
  2. A valid JSON response matching the schema is cast and returned as a structured map in `%Response{}`
  3. A JSON response that does not match the declared schema returns `{:error, :validation_failed}` with field-level detail — never silently passes
  4. Both OpenAI and Anthropic adapters translate the same schema map to their provider-specific structured output format
**Plans**: TBD

### Phase 6: Streaming Transport
**Goal**: Server-Sent Events stream correctly via Finch (not Req), the SSE parser uses a stateful buffer, and all three provider adapters expose chunk parsing
**Depends on**: Phase 5
**Requirements**: STREAM-01, STREAM-02, STREAM-03, STREAM-04
**Success Criteria** (what must be TRUE):
  1. A streaming request uses Finch directly — no Req involvement — and opens a persistent connection that delivers chunks as they arrive
  2. The SSE parser accumulates bytes with `\n\n` boundary detection before JSON decoding — synthetic fragmented-chunk tests pass
  3. Each provider adapter's `parse_chunk/1` converts raw SSE data to `%StreamChunk{}` structs with correct delta and finish_reason fields
  4. Each streaming session spawns exactly one Task — there is no shared singleton GenServer accumulating stream state
**Plans**: TBD

### Phase 7: Streaming + Tools Integration
**Goal**: Streaming and tool calling work correctly together for both OpenAI and Anthropic; chunks are delivered to callers via callback or PID
**Depends on**: Phase 6
**Requirements**: STREAM-05, STREAM-06
**Success Criteria** (what must be TRUE):
  1. A streaming response that includes mid-stream tool call events is parsed correctly — tool arguments arrive complete, not truncated
  2. `PhoenixAI.stream/3` with `on_chunk: fn chunk -> ... end` delivers `%StreamChunk{}` structs to the callback in arrival order
  3. `PhoenixAI.stream/3` with `to: caller_pid` sends `{:chunk, %StreamChunk{}}` messages to the target process
  4. Streaming + tool calling round-trip passes fixture tests for both OpenAI and Anthropic — not just one provider
**Plans**: TBD

### Phase 8: Pipeline Orchestration
**Goal**: Steps execute sequentially where each output feeds the next input, and the pipeline halts and propagates on the first error
**Depends on**: Phase 4
**Requirements**: ORCH-01, ORCH-02, ORCH-03
**Success Criteria** (what must be TRUE):
  1. `PhoenixAI.Pipeline.run(steps, initial_input)` executes each step in order, passing the previous `{:ok, result}` value as input to the next step
  2. If any step returns `{:error, reason}`, the pipeline stops immediately and returns that error — no subsequent steps execute
  3. A three-step pipeline (search → summarize → post) where each step calls an agent completes end-to-end and returns the final step's result
**Plans**: TBD

### Phase 9: Team Orchestration
**Goal**: Multiple agents execute in parallel via Task.async_stream with configurable concurrency, and results are merged by a caller-supplied function
**Depends on**: Phase 4
**Requirements**: ORCH-04, ORCH-05, ORCH-06
**Success Criteria** (what must be TRUE):
  1. `PhoenixAI.Team.run(agent_specs, merge_fn)` starts all agents concurrently and returns only after all complete
  2. `max_concurrency: 5` is the default — no more than 5 agents run simultaneously without explicit override
  3. The merge function receives all results in deterministic order and its return value is the Team's return value
  4. A Task failure (agent crash) returns `{:error, {:task_failed, reason}}` and does not crash the caller
**Plans**: TBD

### Phase 10: Developer Experience
**Goal**: The library is testable without network calls, instrumented with telemetry, has validated option schemas with clear errors, and is published to Hex
**Depends on**: Phase 9
**Requirements**: DX-01, DX-02, DX-03, DX-04, DX-05
**Success Criteria** (what must be TRUE):
  1. `PhoenixAI.TestProvider` returns scripted responses in sequence without any network call — test suites run offline
  2. `:telemetry` events fire for chat start, stop, and exception with token usage metadata attached
  3. Passing invalid options (e.g., wrong type for `temperature:`) returns a clear, human-readable NimbleOptions error — not a cryptic pattern-match failure
  4. `mix hex.publish` succeeds with `~> major.minor` version pins (never patch-level) and ExDoc-generated documentation covers getting started, provider setup, agent creation, and pipeline usage
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Core Foundation | 0/TBD | Not started | - |
| 2. Remaining Providers | 0/TBD | Not started | - |
| 3. Tool Calling | 0/TBD | Not started | - |
| 4. Agent GenServer | 0/TBD | Not started | - |
| 5. Structured Output | 0/TBD | Not started | - |
| 6. Streaming Transport | 0/TBD | Not started | - |
| 7. Streaming + Tools Integration | 0/TBD | Not started | - |
| 8. Pipeline Orchestration | 0/TBD | Not started | - |
| 9. Team Orchestration | 0/TBD | Not started | - |
| 10. Developer Experience | 0/TBD | Not started | - |
