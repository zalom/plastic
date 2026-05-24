# Plastic — Intent-Driven State Management

> Named after **neuroplasticity** — the brain's ability to rewire, adapt, and heal.
> This system is adaptive, malleable, dynamic, and resilient.

Plastic implements the "Intent → Build → Observe → Repeat" SDLC with Zettelkasten-inspired linking between intents. All project state lives in `.plastic/`. Everything is an intent. Built as a Claude Code plugin (skills, hooks, agents, templates). No external dependencies.

## Intents Are the Foundation

ALL work flows through intents. No skill, agent, or workflow creates directories, specs, plans, or artifacts outside the intent system. Intents are the substrate — everything else operates within them.

### Rules for Skills

1. **Before starting any work**, check `.plastic/INDEX.md` for the active intent. If none exists, create one first.
2. **Never create** `docs/superpowers/specs/`, `docs/plans/`, `researches/`, or similar directories. All artifacts go into the active intent's directory.
3. **When a skill produces output** (spec, plan, checklist), write it inside `.plastic/store/NNN--slug-XXXXXX/`.
4. **When a skill completes**, update the intent's `## Build` or `## Observe` sections.
5. **When work is done**, update intent's `## Outcome` and status to `completed`. Update INDEX.md.
6. **Researches are intents** with type `exploration`. No separate folder.

### How Other Skills Work WITH Intents

| Skill | Without Plastic | WITH Plastic |
|-------|-----------------|--------------|
| `superpowers:brainstorming` | Creates `docs/superpowers/specs/*.md` | Spec goes into active intent's dir: `.plastic/store/NNN--slug-XXXXXX/spec.md` |
| `superpowers:writing-plans` | Creates plan in `docs/` or root | Plan goes into `.plastic/store/NNN--slug-XXXXXX/plan.md` |
| `superpowers:test-driven-development` | Works standalone | Tests tracked in active intent's `checklist.md` |
| `superpowers:systematic-debugging` | Works standalone | Bug investigation IS an intent (type: `bug`). Create one. |
| `superpowers:executing-plans` | Reads plan from default location | Reads plan from active intent's `plan.md` |
| `superpowers:verification-before-completion` | Verifies then reports | Updates intent's `## Observe` section and `## Outcome` |
| `superpowers:requesting-code-review` | Reviews current branch | Review scoped to the active intent's work |

### Delegation to External Skills

When Plastic delegates to an external skill (e.g. `superpowers:subagent-driven-development`, `superpowers:executing-plans`, `superpowers:brainstorming`), **Plastic's directory rules OVERRIDE the external skill's defaults.** Specifically:

- `superpowers:writing-plans` wants to save to `docs/superpowers/plans/` → **OVERRIDE:** save to `.plastic/store/NNN--slug-XXXXXX/plan.md`
- `superpowers:brainstorming` wants to save to `docs/superpowers/specs/` → **OVERRIDE:** save to `.plastic/store/NNN--slug-XXXXXX/spec.md`
- `superpowers:subagent-driven-development` creates files per plan → **OK** as long as code files go in the project tree, only planning artifacts go in `.plastic/`
- `superpowers:finishing-a-development-branch` → **OK** as-is, operates on git branches not Plastic directories

**The rule is simple:** code goes in the project. Plans, specs, checklists, savepoints, and all meta-artifacts go in `.plastic/store/NNN--slug-XXXXXX/`. No exceptions. If an external skill tries to create a directory outside `.plastic/` for meta-artifacts, redirect it.

## State System

```
.plastic/
├── config.yml                            # Plugin config
├── INDEX.md                              # Brain's entry point
└── store/
    └── NNN--three-to-five-words-XXXXXX/  # One directory per intent
        ├── intent.md                     # The intent (always present)
        ├── spec.md                       # Brainstorming output (optional)
        ├── plan.md                       # Implementation plan (optional)
        ├── checklist.md                  # Working checklist (optional)
        └── savepoint.md                  # Session state for resume (optional)
```

### Directory Naming

Format: `NNN--three-to-five-words-XXXXXX`
- `NNN` — zero-padded sequential number
- `three-to-five-words` — human-readable slug (3-5 words max)
- `XXXXXX` — 6-char deterministic hash (SHA-256 → base36, Ruby stdlib)

### Intent Lifecycle

```
future → proposed → active → completed | abandoned
```

- **future** — parked for later; agents may research autonomously
- **proposed** — identified but not started
- **active** — currently being worked on
- **completed** — done, outcome recorded
- **abandoned** — dropped or superseded

### Authorship

Intents can be created by humans or AI agents (`author` field): `human`, `claude-code`, `hermes`, `openclaw`, or any agent identifier.

### Creating an Intent

When new work begins:
1. Scan `.plastic/store/` for the next sequential ID
2. Generate hash: `"${CLAUDE_PLUGIN_ROOT}/scripts/hash-intent" "intent name"`
3. Create `.plastic/store/NNN--three-to-five-words-XXXXXX/intent.md`
4. Update `.plastic/INDEX.md` — add to Active section and appropriate cluster
5. Set frontmatter: id, intent, status, type, author, created, tags
6. Add links to related intents in `## Links` section

## Context Management (Start-Save-Continue)

### Save Point
Triggered by PreCompact hook or manually:
1. Find active intent(s) from `.plastic/INDEX.md`
2. Update active intent's `checklist.md` (check off completed items)
3. Update active intent's `savepoint.md` (in-progress, next steps, blockers, discoveries)
4. Update active intent's `intent.md` Build/Observe sections
5. Update `.plastic/INDEX.md`
6. Commit: `git add .plastic/ && git commit -m "chore: savepoint — [intent name]"`
7. Notify user to `/clear`

### Continue
Triggered by UserPromptSubmit hook when user says "continue". Priority order:

**1. Active intents first (resume work):**
1. Read `.plastic/INDEX.md` → find active intent(s)
2. Read active intent's `intent.md` → what and why
3. Read active intent's `savepoint.md` → where we left off
4. Read active intent's `checklist.md` → what's next
5. Read `CLAUDE.md` → project instructions
6. Announce: intent name, current state, next step, blockers
7. Resume

**2. No active intents → offer future intents:**
1. List all future intents from INDEX.md
2. Present them as options: "Which intent would you like to activate?"
3. When user picks one, update `status: active` and move to Active in INDEX.md

**3. Stale future intents (untouched 3+ days) → triage:**
Surface stale intents and ask the user what to do with each:
- **activate** — start working on it now
- **abandon** — mark as abandoned
- **defer to agent** with a mode:
  - `implement` — agent creates plan and executes
  - `research` — agent investigates feasibility, writes findings into intent
  - `ideate` — agent explores problem space, proposes approaches, leaves as `proposed`
