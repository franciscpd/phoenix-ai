# Requirements: PhoenixAI

**Defined:** 2026-03-29
**Core Value:** Developers can build AI-powered agents with skills, sequential pipelines, and parallel execution using idiomatic Elixir/Phoenix patterns and BEAM concurrency primitives.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Core Foundation

- [ ] **CORE-01**: Library initializes as a Mix project with `req`, `jason`, `nimble_options`, `telemetry` as runtime dependencies
- [ ] **CORE-02**: Canonical data model structs exist: `Message`, `Response`, `ToolCall`, `ToolResult`, `Conversation`, `StreamChunk`
- [ ] **CORE-03**: `PhoenixAI.Provider` behaviour defines `chat/2`, `stream/3`, `format_tools/1`, `parse_response/1` callbacks
- [ ] **CORE-04**: Configuration accepts call-site options as primary mechanism with Application env as fallback
- [ ] **CORE-05**: All public functions return `{:ok, result}` or `{:error, reason}` tuples
- [ ] **CORE-06**: Library exposes `child_spec/1` for consumer supervision tree integration — never auto-starts processes

### Providers

- [ ] **PROV-01**: OpenAI provider adapter implements `PhoenixAI.Provider` behaviour with chat completion
- [ ] **PROV-02**: Anthropic provider adapter implements `PhoenixAI.Provider` behaviour with messages API
- [ ] **PROV-03**: OpenRouter provider adapter implements `PhoenixAI.Provider` behaviour (OpenAI-compatible API surface)
- [ ] **PROV-04**: Each provider handles tool result injection in its own adapter (not shared code)
- [ ] **PROV-05**: Provider-specific options pass through via `provider_options: map()` escape hatch
- [ ] **PROV-06**: `PhoenixAI.chat/2` resolves provider from options and delegates to the correct adapter

### Tool Calling

- [ ] **TOOL-01**: `PhoenixAI.Tool` behaviour defines `name/0`, `description/0`, `parameters_schema/0`, `execute/2` callbacks
- [ ] **TOOL-02**: Tools are plain modules — no OTP, no GenServer
- [ ] **TOOL-03**: Agent automatically loops: call provider → detect tool calls → execute tools → re-call provider → until stop
- [ ] **TOOL-04**: Tool call round-trip works with OpenAI (role: "tool" + tool_call_id)
- [ ] **TOOL-05**: Tool call round-trip works with Anthropic (role: "user" + type: "tool_result" content block)

### Agent

- [ ] **AGENT-01**: `PhoenixAI.Agent` GenServer holds conversation state and runs the completion-tool-call loop
- [ ] **AGENT-02**: Agent accepts `provider`, `model`, `system`, `tools` options at start_link
- [ ] **AGENT-03**: `PhoenixAI.Agent.prompt/2` sends user message and returns final response after tool loop completes
- [ ] **AGENT-04**: Agent crashes are isolated — one agent crash does not affect other agents
- [ ] **AGENT-05**: Agent can be started under a DynamicSupervisor via standard `child_spec/1`

### Structured Output

- [ ] **SCHEMA-01**: JSON schema can be defined via plain maps (no Ecto dependency required)
- [ ] **SCHEMA-02**: Provider adapters translate schema to provider-specific structured output parameters
- [ ] **SCHEMA-03**: Response validation casts JSON response to match declared schema
- [ ] **SCHEMA-04**: Validation failure returns `{:error, :validation_failed}` with details — never silently passes

### Streaming

- [ ] **STREAM-01**: SSE streaming uses Finch directly (not Req) for long-running connections
- [ ] **STREAM-02**: SSE parser uses stateful buffer with `\n\n` boundary detection — not line-by-line
- [ ] **STREAM-03**: Each provider adapter implements `parse_chunk/1` for its SSE format
- [ ] **STREAM-04**: Streaming spawns one Task per session — no shared GenServer bottleneck
- [ ] **STREAM-05**: Streaming + tool calling works together (tested combined, not separately)
- [ ] **STREAM-06**: `PhoenixAI.stream/3` accepts callback function or caller PID for chunk delivery

### Orchestration

- [ ] **ORCH-01**: `PhoenixAI.Pipeline.run/3` executes steps sequentially with `{:ok, _}`/`{:error, _}` railway
- [ ] **ORCH-02**: Pipeline step output becomes next step input
- [ ] **ORCH-03**: Pipeline halts on first `{:error, _}` and returns the error
- [ ] **ORCH-04**: `PhoenixAI.Team.run/3` executes agents in parallel via `Task.async_stream`
- [ ] **ORCH-05**: Team exposes `max_concurrency` option with conservative default (5)
- [ ] **ORCH-06**: Team accepts a merge function to combine parallel results

### Developer Experience

- [ ] **DX-01**: `PhoenixAI.TestProvider` returns scripted responses without network calls
- [ ] **DX-02**: Telemetry events fire for chat start/stop/exception with token usage metadata
- [ ] **DX-03**: NimbleOptions schemas validate all public function options with clear error messages
- [ ] **DX-04**: ExDoc documentation covers getting started, provider setup, agent creation, and pipeline usage
- [ ] **DX-05**: Mix library publishes to Hex with `~> major.minor` dependency pins (not patch-level)

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Extended Features

- **V2-01**: Provider failover — try providers in order on failure (sequential retry)
- **V2-02**: Named agent GenServer with `via_tuple` for long-running supervised sessions
- **V2-03**: Inline/anonymous agent helper (`PhoenixAI.prompt/2` without defining a module)
- **V2-04**: Conversation history persistence protocol (callbacks for Ecto, ETS, Redis, etc.)
- **V2-05**: Phoenix LiveView/Channels streaming helpers (`stream_to_socket/3`)
- **V2-06**: Image/audio/multimodal input support
- **V2-07**: MCP client support as tool source
- **V2-08**: Rate limiter GenServer with token bucket per provider
- **V2-09**: Context window management helpers (keep-last-N, summarize, sliding window)

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Built-in database persistence | Anti-feature — couples library to Ecto/Postgres, kills non-Phoenix adoption |
| Web UI / LiveView components | Not a UI library — consumers own the UI |
| Embeddings / vector search | Separate concern — companion library later |
| RAG pipeline | Domain-specific, too complex for core — document as pattern using Pipeline primitive |
| Provider-specific feature wrappers | Extended thinking, prompt caching, web search — unstable APIs, use `provider_options` passthrough |
| Python subprocess / Nx.Serving | Local model inference is a separate concern — Bumblebee ecosystem handles this |
| MCP server hosting | Separate product (laravel/ai has Laravel MCP separately) |
| Fine-tuning / training | Inference-only library |
| Custom OTP framework layer | Anti-pattern — expose OTP primitives directly, don't wrap them |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| CORE-01 | Phase 1 | Pending |
| CORE-02 | Phase 1 | Pending |
| CORE-03 | Phase 1 | Pending |
| CORE-04 | Phase 1 | Pending |
| CORE-05 | Phase 1 | Pending |
| CORE-06 | Phase 1 | Pending |
| PROV-01 | Phase 1 | Pending |
| PROV-02 | Phase 2 | Pending |
| PROV-03 | Phase 2 | Pending |
| PROV-05 | Phase 2 | Pending |
| PROV-06 | Phase 2 | Pending |
| PROV-04 | Phase 3 | Pending |
| TOOL-01 | Phase 3 | Pending |
| TOOL-02 | Phase 3 | Pending |
| TOOL-03 | Phase 3 | Pending |
| TOOL-04 | Phase 3 | Pending |
| TOOL-05 | Phase 3 | Pending |
| AGENT-01 | Phase 4 | Pending |
| AGENT-02 | Phase 4 | Pending |
| AGENT-03 | Phase 4 | Pending |
| AGENT-04 | Phase 4 | Pending |
| AGENT-05 | Phase 4 | Pending |
| SCHEMA-01 | Phase 5 | Pending |
| SCHEMA-02 | Phase 5 | Pending |
| SCHEMA-03 | Phase 5 | Pending |
| SCHEMA-04 | Phase 5 | Pending |
| STREAM-01 | Phase 6 | Pending |
| STREAM-02 | Phase 6 | Pending |
| STREAM-03 | Phase 6 | Pending |
| STREAM-04 | Phase 6 | Pending |
| STREAM-05 | Phase 7 | Pending |
| STREAM-06 | Phase 7 | Pending |
| ORCH-01 | Phase 8 | Pending |
| ORCH-02 | Phase 8 | Pending |
| ORCH-03 | Phase 8 | Pending |
| ORCH-04 | Phase 9 | Pending |
| ORCH-05 | Phase 9 | Pending |
| ORCH-06 | Phase 9 | Pending |
| DX-01 | Phase 10 | Pending |
| DX-02 | Phase 10 | Pending |
| DX-03 | Phase 10 | Pending |
| DX-04 | Phase 10 | Pending |
| DX-05 | Phase 10 | Pending |

**Coverage:**
- v1 requirements: 38 total
- Mapped to phases: 38
- Unmapped: 0

---
*Requirements defined: 2026-03-29*
*Last updated: 2026-03-29 after roadmap creation*
