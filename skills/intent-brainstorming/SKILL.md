---
name: plastic-intent-brainstorming
description: "Explore intent requirements and design before implementation, through conversational prose questions asked one at a time (no multiple-choice chips), persisting each owner ruling immediately as an insight. Produces the enriched Why (Context and Decisions) in the active intent directory; hands off to /plastic-intent-speccing for spec.md."
user-invocable: true
---

# Brainstorming Ideas Into Designs

Help turn ideas into fully formed designs through natural collaborative dialogue.

Start by understanding the current project context, then ask questions one at a time, in prose, to refine the idea. Once you understand what you're building, present the design and collect the owner's rulings on it. This skill's product is the enriched Why, not spec.md.

<HARD-GATE>
Do NOT invoke any implementation skill, write any code, scaffold any project, or take any implementation action until you have presented a design and the user has ruled on it. This applies to EVERY project regardless of perceived simplicity.
</HARD-GATE>

## Active Intent Gate

Before proceeding, resolve the active intent:

1. **Detect store:** Read `~/.plastic/projects.yml`, match CWD against registered project paths. If match → project store at `~/.plastic/projects/{slug}/store/`. If no match → global store at `~/.plastic/store/`.
2. **Find active intent:** Read `INDEX.md` from the detected store. Look under `## Active`. If exactly one → use it. If multiple → ask which. If none → refuse: "No active intent. Create one first with /plastic-intent-creating"
3. **Resolve intent directory:** `{store}/store/{id}--{slug}/`

All artifacts go to the intent directory. Never write to external paths.

## Anti-Pattern: "This Is Too Simple To Need A Design"

Every project goes through this process. A todo list, a single-function utility, a config change: all of them. "Simple" projects are where unexamined assumptions cause the most wasted work. The design can be short (a few sentences for truly simple projects), but you MUST present it and get a ruling.

## Checklist

You MUST create a task for each of these items and complete them in order:

1. **Explore project context**: check files, docs, recent commits, read active intent
2. **Grill in prose**: ask conversational prose questions, one at a time, no multiple-choice chips; understand purpose/constraints/success criteria
3. **Propose 2-3 approaches**: with trade-offs and your recommendation
4. **Present design**: in sections scaled to their complexity, get a ruling after each section
5. **Collect rulings**: for each owner ruling, immediately persist it (see Collect rulings below); never batch
6. **Hand off to /plastic-intent-speccing**: the enriched Why is done; do not author spec.md here

## Process Flow

The Checklist above states the ordered flow (steps 1-6). For the same flow as a
diagram, read `references/design-principles.md`.

**The terminal state is the handoff below.** Do NOT invoke any implementation skill and do NOT write spec.md. Brainstorming's product is the enriched Why.

## The Process

**Understanding the idea:**
- QMD-first (when available): before scanning the store with grep/Read for prior decisions, specs, or outcomes, run `ruby ~/.plastic/scripts/qmd-sync search "<terms>"` to surface candidate, prior, or related intents, then open the authoritative intent file for any hit you act on. The command is a no-op when QMD is absent, so fall back to the existing INDEX.md / file scan.
- Check out the current project state first (files, docs, recent commits)
- Before asking detailed questions, assess scope: if the request describes multiple independent subsystems (e.g., "build a platform with chat, file storage, billing, and analytics"), flag this immediately. Don't spend questions refining details of a project that needs to be decomposed first.
- If the project is too large for a single spec, help the user decompose into sub-projects: what are the independent pieces, how do they relate, what order should they be built? Then brainstorm the first sub-project through the normal design flow. Each sub-project gets its own Why → spec → plan → implementation cycle.
- For appropriately-scoped projects, ask questions one at a time, in prose, to refine the idea
- Ask conversational prose questions, not multiple-choice chips. A short menu of named options is fine when the choice is genuinely enumerable, but phrase it as a sentence, not a bulleted picker.
- Only one question per message - if a topic needs more exploration, break it into multiple questions
- Focus on understanding: purpose, constraints, success criteria

**Exploring approaches:**
- Propose 2-3 different approaches with trade-offs
- Present options conversationally with your recommendation and reasoning
- Lead with your recommended option and explain why

**Presenting the design:**
- Once you believe you understand what you're building, present the design
- Scale each section to its complexity: a few sentences if straightforward, up to 200-300 words if nuanced
- Ask after each section whether it looks right so far
- Cover: architecture, components, data flow, error handling, testing
- Be ready to go back and clarify if something doesn't make sense

**Design for isolation and clarity, and working in existing codebases:** before
proposing a design, read `references/design-principles.md` for unit-boundary
guidance (what makes a good interface, when a file has grown too large) and
existing-codebase guidance (follow established patterns, fold in targeted
improvements without unrelated refactoring).

## Collect rulings

Each owner ruling triggers one immediate persist call, never a batch. The moment the
owner rules on a question or a design section, before moving to the next one, run:

```
ruby ~/.plastic/scripts/insight-append {intent_dir} "<ruling text>" --stage Why --author human
```

When a later ruling conflicts with an earlier one already on record, append a new
insight that names the superseded ruling and states plainly that this one supersedes
it. Both insights stay on record; the later one wins.

When presenting a batch of design options or rulings for the owner to choose, read
`~/.plastic/_decision-tables.md` and follow the numbered-table procedure.

## Handoff

Why exploration complete. The enriched Why is captured (Context, Decisions, one
insight per ruling). Invoke /plastic-intent-speccing to consolidate it into spec.md.
Do not author spec.md here.

## Gate position

- **Before:** an active intent exists with the lock armed.
- **Produces:** the enriched Why (`## Context`, `### Decisions`, one `## Insights` entry per ruling).
- **Next:** /plastic-intent-speccing consolidates the enriched Why into spec.md.

Read `../plastic-conventions/references/lifecycle-and-savepoints.md` for the subagent
report-home contract this handoff relies on. This path resolves relative to this skill's own
installed directory.

## Key Principles

- **One question at a time** - Don't overwhelm with multiple questions
- **Prose, not chips** - Ask conversational prose questions; skip multiple-choice menus
- **YAGNI ruthlessly** - Remove unnecessary features from all designs
- **Explore alternatives** - Always propose 2-3 approaches before settling
- **Incremental validation** - Present design, collect a ruling before moving on
- **Be flexible** - Go back and clarify when something doesn't make sense
