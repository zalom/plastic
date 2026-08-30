---
name: plastic-intent-speccing
description: >-
  Thinking mode for an intent: the conversation that turns an idea into rulings, the
  research that backs them, and the action files that say how the work runs. Use when the
  user wants to think a request through before building it, says "let's design this",
  "brainstorm", "grill me", "research this first", "spec this intent", "write the spec",
  or when a prompt is too vague to run directly and the direct skill routes here. Also
  fires on an indirect ask that never names a spec, such as "turn what we just discussed
  into the contract the work runs from." Absorbs what the former intent-brainstorming,
  intent-grilling, and intent-researching skills used to do (intent 304).
user-invocable: true
---

# Intent Speccing: thinking mode

One skill for the whole thinking conversation on an intent. It asks one question at a time,
records every owner ruling the moment it lands, grills when asked, deposits research in
`resources/`, and ends by writing the action files the work runs from and consolidating the
rulings into `spec.md`. There is no separate brainstorm, grill, or research skill; those are
the modes below.

## Active intent

Resolve the active intent before anything else: read `~/.plastic/projects.yml`, match the
working directory against registered project paths (a match means the project store at
`~/.plastic/projects/{slug}/store/`, no match means `~/.plastic/store/`), then read that
store's `INDEX.md` under `## Active`. Exactly one active intent is the one to work; several
means ask which; none means stop and say so ("No active intent. Create one first with
/plastic-intent-creating"). Every artifact goes into `{store}/{id}--{slug}/`; never write
outside it.

## The conversation

QMD-first: before scanning the store by hand for prior decisions, specs, or research, run
`ruby ~/.plastic/scripts/qmd-sync search "<terms>"` and open the authoritative intent file for
any hit you act on. The command is a no-op when QMD is absent.

1. **Context first.** Check the project state (files, docs, recent commits) and the intent's
   `## Context` and `## Insights`. Assess scope: a request that describes several independent
   subsystems is decomposed first, one thinking conversation per piece, before any detail
   question is spent.
2. **One question per message, in prose.** No multiple-choice chips; a short menu of named
   options is fine when the choice is genuinely enumerable, phrased as a sentence. Focus on
   purpose, constraints, and success criteria. Before asking how something works, look:
   in a codebase the answer is usually on disk.
3. **Propose two or three approaches** with trade-offs, leading with the recommendation and
   the reason for it. YAGNI: strip what the design does not need.
4. **Present the design in sections** scaled to their complexity (a few sentences when
   straightforward, up to 300 words when nuanced): architecture, components, data flow,
   error handling, testing. Get a ruling after each section. Read
   `references/design-principles.md` before proposing a design for the unit-boundary and
   existing-codebase guidance (follow established patterns, no unrelated refactoring).
5. **Record every ruling as it lands.** The moment the owner rules, before the next question:
   ```
   ruby ~/.plastic/scripts/insight-append {intent_dir} "<ruling text>" --stage Why --author human
   ```
   Never batch. A later ruling that conflicts with an earlier one gets a new insight naming
   the superseded one; both stay on record and the later wins. When presenting a batch of
   options for the owner to pick from, read `~/.plastic/_decision-tables.md` and follow the
   numbered-table procedure.

No implementation starts until a design has been presented and ruled on. That holds for a
config change and a one-function utility as much as for a subsystem; the design can be three
sentences, but it is presented.

### Grill mode

When the owner says "grill me" or asks to stress-test a plan or design, the same conversation
turns relentless. Identify the root in one sentence and restate it. Walk the decision tree
branch by branch: state the branch, ask a specific question, lead with your own recommended
answer, resolve before moving on, name dependencies between decisions and resolve the
upstream one first. Do not accept "it depends" without "on what?"; do not skip edge cases; do
not assume when you can verify; challenge assumptions ("why not the alternative?"). Every
three or four questions, summarize what is decided. At natural checkpoints, about every ten
questions, offer to continue or to pause and capture what is decided; a pause records every
ruling so far and stops. When all branches are resolved, list the decisions and the deferred
items, then offer the hand-off below.

### Research mode

When a question needs evidence rather than a ruling, research it and deposit the report in
`{intent_dir}/resources/{type}--{topic}.md`, with `{type}` one of `deep-research`,
`competitive-analysis`, `technical-spike`, `reference`, `landscape-survey` and `{topic}` in
kebab-case. Choose the depth and say why: shallow (one or two searches plus a look at the
code, minutes) for a narrow factual question; deep (several sources, cross-checked, a
landscape or an architectural decision, or when a wrong answer would cause an architectural
mistake) through the harness's deep-research capability when it has one, else a manual
fan-out of searches. The report carries a summary, findings with citations, sources, and a
"Relevance to intent" section; tables for findings and comparisons. Log one line in the
intent's `## Insights` naming the file and the key finding. Research does not chain to
another step; the conversation decides what to do with it.

## Closing the conversation

When the rulings are enough to build from:

1. **Write the action files.** Every ruling that says how the work runs lands in
   `actions/ACTION_N.md` (at least one real file, no placeholder): the files to touch, the
   order, the tests that prove each step, the rules. The action files are what direct mode or
   an auto team executes; they exist before the work runs.
2. **Consolidate `spec.md`** from the rulings, section by section in template order. Read
   `references/per-section-fill-rules.md` when filling the template. Build the ruling ledger
   in fixed order first: `## Context` and `### Decisions`, then `## Insights` newest-last so a
   later ruling supersedes an earlier one, then `resources/discovery--<slug>.md`, then any
   other `resources/*.md`. Encode every ruling into its section; a collapsed single-line
   section is complete when it names everything. If a section cannot be filled from the
   ledger, stop and ask for the missing ruling; never invent scope. A spec.md left as the
   placeholder is backfilled from the record at close (`## Problem`, `## Decisions`,
   `## Acceptance Criteria`; the rest stays stub text), so consolidate only when the
   rulings say more than the record already does.
3. **Self-verify.** Read `references/self-verify-checklist.md` before presenting; fix any
   failing check and re-verify from the top.
4. **Present and hand off.** Present `spec.md` and the action files. Then offer the routes:
   run it now inline when the work is small enough for direct mode; hand to `plastic-auto`
   when the owner says auto and the checklist above passes (all decisions resolved, scope
   bounded, dependencies named, success criteria defined); or keep thinking.

Report, in this order: which files were written (`spec.md` new or rewritten, the action
files), the count of acceptance criteria, which `## Insights` rulings superseded an earlier
decision and where each landed, and the route chosen. If step 2 stopped for a missing
ruling, report that instead: which section, what is missing, the question put to the owner.

## References

| Trigger | Read |
|---|---|
| Before proposing a design (unit boundaries, existing codebases) | `references/design-principles.md` |
| Filling the spec template (closing step 2) | `references/per-section-fill-rules.md` |
| Self-verifying before presenting (closing step 3) | `references/self-verify-checklist.md` |
