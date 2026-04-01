# Milestones

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
