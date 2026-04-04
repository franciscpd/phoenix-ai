# Milestones

## v0.2.0 — Usage Normalization

**Shipped:** 2026-04-04
**Phases:** 2 | **Plans:** 2 | **Tests:** 326 (15 new)
**Timeline:** 1 day (Apr 3–4, 2026)
**Stats:** 2,776 LOC (lib), 4,752 LOC (test), 22 commits

### Key Accomplishments

1. `PhoenixAI.Usage` normalized struct with `from_provider/2` factory for OpenAI, Anthropic, OpenRouter + generic fallback
2. Auto-calculated `total_tokens` when provider omits it (Anthropic, unknown providers)
3. `Response.usage` and `StreamChunk.usage` carry `Usage.t()` instead of raw maps — no raw usage maps escape adapter boundaries
4. Backward compatibility via `provider_specific` field preserving original raw provider map
5. OpenRouter adapter gained its own `parse_chunk/1` (previously delegated to OpenAI) for correct provider atom dispatch
6. Stream accumulator uses explicit nil checks instead of `||` truthiness for Usage struct compatibility

### Tech Debt

- `PhoenixAI.Conversation` stub module — dead code, never integrated (carried from v0.1.0)

### Archive

- [Roadmap](milestones/v0.2.0-ROADMAP.md)
- [Requirements](milestones/v0.2.0-REQUIREMENTS.md)
- [Audit](milestones/v0.2.0-MILESTONE-AUDIT.md)

---

## v0.1.0 — Initial Release

**Shipped:** 2026-03-31
**Phases:** 10 | **Plans:** 10 | **Tests:** 311
**Timeline:** 3 days (Mar 29–31, 2026)
**Stats:** 2,647 LOC (lib), 4,555 LOC (test), 141 commits

### Key Accomplishments

1. Multi-provider AI integration (OpenAI, Anthropic, OpenRouter) with unified dispatch API
2. Tool calling with per-provider wire format handling and automatic completion loop
3. Stateful Agent GenServer with conversation history and DynamicSupervisor support
4. Structured output with JSON schema validation (no Ecto dependency)
5. Real-time SSE streaming via Finch with combined streaming+tools support
6. Pipeline (sequential) and Team (parallel) orchestration primitives
7. Developer experience: TestProvider sandbox, telemetry spans, NimbleOptions validation, ExDoc guides
8. Published to Hex as `phoenix_ai ~> 0.1.0`

### Tech Debt

- `PhoenixAI.Conversation` stub module — dead code, never integrated

### Archive

- [Roadmap](milestones/v0.1.0-ROADMAP.md)
- [Requirements](milestones/v0.1.0-REQUIREMENTS.md)
- [Audit](milestones/v0.1.0-MILESTONE-AUDIT.md)
