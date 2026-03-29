# Phase 2: Remaining Providers - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-29
**Phase:** 02-remaining-providers
**Areas discussed:** OpenRouter code reuse, Anthropic API format, Default model OpenRouter, Tests and fixtures

---

## OpenRouter: Code Reuse Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Adapter independente | Copy OpenAI structure, adapt headers/URL. Self-contained, zero coupling. | ✓ |
| Delegar ao OpenAI | OpenRouter calls OpenAI.chat/2 internally, changing base_url and headers. | |
| Módulo compartilhado | Extract common logic to OpenAICompat module, both adapters use it. | |

**User's choice:** Adapter independente (Recommended)
**Notes:** Clean separation preferred. Each adapter owns its full implementation.

---

## Anthropic: System Message Handling

| Option | Description | Selected |
|--------|-------------|----------|
| Extrair automaticamente | Adapter detects role: :system messages, extracts to top-level system param. | ✓ |
| Via opts | System prompt as separate opt: chat(msgs, system: "..."). | |
| Claude decide | Let implementation choose the best approach. | |

**User's choice:** Extrair automaticamente (Recommended)
**Notes:** Caller uses same message list regardless of provider. Adapter handles translation.

---

## Anthropic: API Version Header

| Option | Description | Selected |
|--------|-------------|----------|
| 2023-06-01 | Current stable version, supports Messages API, tool use, streaming. | ✓ |
| Claude decide | Use most appropriate version at implementation time. | |

**User's choice:** 2023-06-01 (Recommended)
**Notes:** User was surprised the version string is from 2023 — clarified it's an API contract version (like Stripe), not a feature date. All current features work with it.

---

## Default Model: OpenRouter

| Option | Description | Selected |
|--------|-------------|----------|
| Sem default | Require explicit model:, return {:error, :model_required} if omitted. | ✓ |
| openai/gpt-4o | Use OpenRouter format with gpt-4o default. | |
| auto | OpenRouter's automatic model selection. | |

**User's choice:** Sem default (Recommended)
**Notes:** OpenRouter has hundreds of models — choosing a default would be arbitrary.

---

## Testing Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Mesmo padrão Phase 1 | Fixtures JSON + Mox, same as OpenAI tests. | |
| Fixtures + contract tests | Fixtures plus cross-adapter contract tests verifying consistent Response format. | ✓ |
| Claude decide | Follow what makes sense for adequate coverage. | |

**User's choice:** Fixtures + contract tests
**Notes:** Contract tests ensure all adapters behave consistently at the AI.chat/2 level.

---

## Claude's Discretion

- Internal Req request construction details
- Anthropic content block handling for simple text
- OpenRouter-specific headers (HTTP-Referer, X-Title)
- Contract test module structure
- Error message formatting per provider

## Deferred Ideas

None — discussion stayed within phase scope
