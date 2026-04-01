# Phase 1: Core Foundation - Context

**Gathered:** 2026-03-29
**Status:** Ready for planning

<domain>
## Phase Boundary

The library's structural skeleton: canonical data model structs, Provider behaviour contract, HTTP transport layer (Req for sync, Finch for streaming), a working OpenAI adapter with synchronous chat, call-site configuration with env var fallback, and child_spec for consumer supervision tree integration. No auto-starting processes.

</domain>

<decisions>
## Implementation Decisions

### Naming & API Surface
- **D-01:** Package name is `phoenix_ai` on Hex. Top-level module namespace is `PhoenixAI`.
- **D-02:** Main public API module is `AI` — short and clean, inspired by laravel/ai's `AI::agent()`. Usage: `AI.chat(messages, provider: :openai)`.
- **D-03:** Data model structs are flat under `PhoenixAI.*` — e.g., `PhoenixAI.Message`, `PhoenixAI.Response`, `PhoenixAI.ToolCall`, `PhoenixAI.ToolResult`, `PhoenixAI.Conversation`, `PhoenixAI.StreamChunk`.
- **D-04:** Providers referenced by atom shortcut: `provider: :openai`, `:anthropic`, `:openrouter`. The `AI` module resolves atoms to provider modules internally.

### Configuration
- **D-05:** Call-site options are the primary configuration mechanism. Resolution order: call-site opts > config.exs > System.get_env fallback.
- **D-06:** Multi-tenant support from v1 — each call can have its own API key via call-site opts.
- **D-07:** Automatic env var fallback: `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `OPENROUTER_API_KEY` are read via `System.get_env/1` when not provided in config or call-site.
- **D-08:** Each provider has a default model. For Anthropic, use model IDs without the date suffix (e.g., `claude-sonnet-4-5`, not `claude-sonnet-4-5-20250514`).

### Provider Behaviour
- **D-09:** `PhoenixAI.Provider` behaviour with core required callbacks (`chat/2`, `parse_response/1`) and optional callbacks (`stream/3`, `format_tools/1`, `parse_chunk/1`) via `@optional_callbacks`.
- **D-10:** Provider-specific options pass through via `provider_options: %{...}` map — explicit and transparent. Unknown options do NOT silently pass through.

### Mix Project Setup
- **D-11:** Elixir `~> 1.18` minimum. OTP 26+ required.
- **D-12:** Testing strategy: Mox for behaviour-based mocking + fixture JSON files with recorded real provider responses.
- **D-13:** GitHub Actions CI from day one: `mix test`, `mix format --check-formatted`, `mix credo`, `mix dialyzer`.
- **D-14:** Standard Mix lib directory structure: `lib/phoenix_ai/` with `providers/` subdirectory. Tests mirror under `test/phoenix_ai/`.
- **D-15:** Quality tooling: Credo, Dialyxir, mix format, ExCoveralls — all included from the start.

### Claude's Discretion
- Exact Req wrapper implementation details
- Internal module organization beyond the declared structure
- Specific NimbleOptions schema definitions
- ExDoc configuration and theme

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project Research
- `.planning/research/STACK.md` — Technology stack recommendations with versions and rationale
- `.planning/research/ARCHITECTURE.md` — Component boundaries, data flows, provider behaviour contract definition
- `.planning/research/PITFALLS.md` — Critical pitfalls to avoid (leaky abstraction, config anti-patterns, supervision pollution)
- `.planning/research/SUMMARY.md` — Synthesized findings with top 5 impactful decisions

### laravel/ai Reference
- `https://github.com/laravel/ai` — API surface inspiration (agents, tools, structured output patterns)
- `https://laravel.com/docs/12.x/ai-sdk` — Official Laravel AI SDK docs for API parity reference

### Elixir Patterns
- Elixir Library Guidelines (hexdocs.pm) — Supervision, config, dependency guidelines
- Mocks and Explicit Contracts (Dashbit Blog) — Mox/Behaviour pattern for testing
- NimbleOptions docs (hexdocs.pm) — Config validation patterns

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- None — greenfield project, no existing code

### Established Patterns
- None yet — this phase establishes the foundational patterns

### Integration Points
- Consumers will add `PhoenixAI.child_spec([])` to their supervision tree
- `AI` module is the primary entry point consumers import

</code_context>

<specifics>
## Specific Ideas

- API should feel like laravel/ai's `AI::agent()` — the `AI.chat/2` naming mirrors this
- Anthropic model defaults should use short IDs without date suffix (e.g., `claude-sonnet-4-5`)
- The library should feel idiomatic to Elixir developers — behaviours, not protocols; tuples, not exceptions

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 01-core-foundation*
*Context gathered: 2026-03-29*
