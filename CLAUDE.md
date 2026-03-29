# CLAUDE.md

## .planning/ — Single Source of Truth

All planning artifacts MUST go in `.planning/`. Never outside it.

```
.planning/
└── phases/
    └── {N}-{slug}/          ← one folder per GSD phase (e.g. 01-auth)
        ├── DISCUSS.md        ← gsd:discuss output
        ├── BRAINSTORM.md     ← superpowers:brainstorm output
        ├── PLAN.md           ← superpowers:write-plan output
        ├── PROGRESS.md       ← superpowers:execute-plan tracking
        └── VERIFY.md         ← superpowers:requesting-code-review output
```

Before writing any artifact, MUST identify the active GSD phase and resolve its folder: `.planning/phases/{N}-{slug}/`. Create the folder if it does not exist. All Superpowers outputs for that phase go inside it.

---

## Workflow — Follow This Order Exactly

```
gsd:discuss → brainstorm → write-plan → execute-plan → gsd:verify
```

> `$PHASE` = active GSD phase folder, e.g. `.planning/phases/01-auth`

### Phase 1 — discuss
- Trigger: any new feature, task or bug with unclear scope
- MUST capture: requirements, scope, what's out of scope, priority
- MUST save output to `$PHASE/DISCUSS.md`
- MUST NOT proceed without explicit user approval

### Phase 2 — brainstorm
- Trigger: automatically after discuss approval
- MUST invoke `/superpowers:brainstorm` using `$PHASE/DISCUSS.md` or `$PHASE/{N}-CONTEXT.md` as context
- Focus: technical approach, architecture, trade-offs, Laravel patterns
- MUST save output to `$PHASE/BRAINSTORM.md`
- MUST NOT proceed without explicit user approval

### Phase 3 — write-plan
- Trigger: automatically after brainstorm approval
- MUST invoke `/superpowers:write-plan` using `$PHASE/DISCUSS.md` or `$PHASE/{N}-CONTEXT.md` + `$PHASE/BRAINSTORM.md` as input
- Output MUST include: affected files, atomic tasks, verify commands, commit messages
- MUST save output to `$PHASE/PLAN.md`
- MUST NOT proceed without explicit user approval

### Phase 4 — execute-plan
- Trigger: automatically after plan approval
- MUST invoke `/superpowers:execute-plan` using `$PHASE/PLAN.md`
- MUST follow TDD: write failing test → implement → pass (RED → GREEN → REFACTOR)
- MUST track progress in `$PHASE/PROGRESS.md`
- MUST commit atomically per logical task immediately after verify passes

### Phase 5 — verify
- Trigger: automatically after execute-plan completes
- MUST invoke `/superpowers:requesting-code-review`
- MUST run `php artisan test && php artisan pint` — nothing is done without passing evidence
- MUST save output to `$PHASE/VERIFY.md`


## Skip Rules

| Situation | Skip |
|---|---|
| Scope is already clear | Skip discuss, start at brainstorm |
| Approach is already clear | Skip brainstorm, start at write-plan |
| Small well-defined task | Skip discuss + brainstorm, start at write-plan |
| Known bug with clear fix | Use `/superpowers:systematic-debugging` directly |

---

## Commits

```
type(scope): description
```
Types: `feat | fix | refactor | test | docs | style | chore`
One commit per logical task. Never commit broken code.

---

## Rules

- Bugs before features. Max 2–3 WIP tasks.
- Never deploy without explicit approval.
- Never skip phases without a skip rule justifying it.
- Always ask when scope or approach is unclear.
