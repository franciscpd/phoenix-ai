# Phase 2: Remaining Providers - Context

**Gathered:** 2026-03-29
**Status:** Ready for planning

<domain>
## Phase Boundary

All three v1 providers (OpenAI, Anthropic, OpenRouter) are available through a unified dispatch function (`AI.chat/2`), with provider-specific options passthrough. This phase adds the Anthropic and OpenRouter adapters — the dispatch and config infrastructure already exists from Phase 1.

</domain>

<decisions>
## Implementation Decisions

### OpenRouter Adapter
- **D-01:** OpenRouter adapter is fully independent — no code sharing or delegation to OpenAI adapter. Self-contained `chat/2`, `parse_response/1`, and `format_messages/1`. Zero coupling between adapters.
- **D-02:** OpenRouter uses OpenAI-compatible API surface but with its own base URL (`https://openrouter.ai/api/v1`) and authentication headers.

### Anthropic Adapter
- **D-03:** Anthropic adapter automatically extracts `role: :system` messages from the message list and places them as the top-level `system` parameter in the API request body. The caller uses the same message list format regardless of provider.
- **D-04:** Multiple system messages are concatenated with `\n\n` separator into a single system string.
- **D-05:** Anthropic API version header defaults to `2023-06-01` (current stable version). Override available via `provider_options: %{"anthropic-version" => "..."}`.
- **D-06:** Content format uses simple strings for Phase 2 (content blocks with types will be needed in Phase 3 for tool results).

### Default Models
- **D-07:** OpenRouter has NO default model — caller must pass `model: "provider/model-name"`. Returns `{:error, :model_required}` if omitted.
- **D-08:** OpenAI default: `gpt-4o` (from Phase 1). Anthropic default: `claude-sonnet-4-5` (from Phase 1, no date suffix).

### Provider Dispatch
- **D-09:** `AI.chat/2` dispatch and `AI.provider_module/1` mapping already exist from Phase 1. Phase 2 adds the adapter modules that make `:anthropic` and `:openrouter` atoms resolve to working implementations.
- **D-10:** Unknown provider returns `{:error, {:unknown_provider, atom}}` — already implemented.

### Testing Strategy
- **D-11:** Fixtures JSON with recorded real provider responses (same pattern as Phase 1 OpenAI tests).
- **D-12:** Contract tests that verify ALL adapters return consistent `%Response{}` format for equivalent inputs — ensures provider-agnostic behavior at the `AI.chat/2` level.
- **D-13:** Test scenarios: success response, HTTP error, missing api_key, parse_response correctness, provider_options passthrough.

### Claude's Discretion
- Internal Req request construction details
- Anthropic content block handling for simple text (string vs single-element array)
- OpenRouter-specific headers (HTTP-Referer, X-Title) — include if useful
- Contract test module structure and organization
- Error message formatting per provider

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project Research
- `.planning/research/STACK.md` — Technology stack with versions and rationale
- `.planning/research/ARCHITECTURE.md` — Component boundaries, provider behaviour contract
- `.planning/research/PITFALLS.md` — Critical pitfalls (leaky abstraction, config anti-patterns)
- `.planning/research/SUMMARY.md` — Synthesized findings with top decisions

### Phase 1 Context
- `.planning/phases/01-core-foundation/01-CONTEXT.md` — Naming, config cascade, provider behaviour decisions

### Existing Code (Phase 1 output)
- `lib/phoenix_ai/providers/openai.ex` — Reference adapter implementation (template for new adapters)
- `lib/phoenix_ai/provider.ex` — Provider behaviour contract
- `lib/ai.ex` — Dispatch logic, provider_module mapping
- `lib/phoenix_ai/config.ex` — Config cascade with env var fallback

### Provider API Docs
- Anthropic Messages API: `https://docs.anthropic.com/en/api/messages`
- OpenRouter API: `https://openrouter.ai/docs/api-reference`

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `PhoenixAI.Providers.OpenAI` — Complete adapter serving as structural template (chat/2, parse_response/1, format_messages/1, maybe_put/3)
- `PhoenixAI.Error` struct — Shared error format with `status`, `message`, `provider` fields
- `PhoenixAI.Response` struct — Canonical response with `content`, `finish_reason`, `model`, `usage`, `tool_calls`, `provider_response`
- `PhoenixAI.Message` struct — Canonical message with `role`, `content`, `tool_calls`, `tool_call_id`
- `PhoenixAI.Config.resolve/2` — Already handles `:anthropic` and `:openrouter` env vars and defaults

### Established Patterns
- Provider adapters use `@behaviour PhoenixAI.Provider` and implement required callbacks
- HTTP via `Req.post/2` with json body and headers
- Error responses parsed from provider-specific JSON structure into `%Error{}`
- Tool calls parsed but not executed (Phase 3 concern)
- `provider_options` merged directly into request body via `Map.merge/2`

### Integration Points
- `AI.provider_module(:anthropic)` → `PhoenixAI.Providers.Anthropic` (mapping exists, module doesn't yet)
- `AI.provider_module(:openrouter)` → `PhoenixAI.Providers.OpenRouter` (mapping exists, module doesn't yet)
- `PhoenixAI.Config` already has `@env_vars` entries and `@default_models` for anthropic (no default model for openrouter — needs adding the `:model_required` validation)

</code_context>

<specifics>
## Specific Ideas

- Each adapter should be fully self-contained — the "copy and adapt" approach is preferred over DRY abstractions at this stage
- Anthropic version header (`2023-06-01`) is the stable API contract version, not a feature date — all current features work with it
- OpenRouter requiring explicit model selection prevents surprising defaults when routing across providers

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 02-remaining-providers*
*Context gathered: 2026-03-29*
