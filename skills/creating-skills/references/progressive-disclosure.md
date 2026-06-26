# Progressive Disclosure

The canonical load-level model for Plastic skills, agents, and hooks. Every other
reference and the SKILL.md body point here for this model and must not restate it (C7).
Read it before authoring any skill body, before splitting content into `references/`,
and before deciding where a file goes (scripts, references, or assets).

## Contents

- [The three load levels](#the-three-load-levels)
- [When to split the body into references](#when-to-split-the-body-into-references)
- [Bucket selection: scripts vs references vs assets](#bucket-selection-scripts-vs-references-vs-assets)
- [Reference-link discipline (C4)](#reference-link-discipline-c4)
- [One level deep, with a table of contents (C5, C6)](#one-level-deep-with-a-table-of-contents-c5-c6)
- [Store each fact once (C7)](#store-each-fact-once-c7)
- [Cross-reference other skills by name (C8)](#cross-reference-other-skills-by-name-c8)
- [Ship only what does the job (C9)](#ship-only-what-does-the-job-c9)
- [The thin-router pattern (C10)](#the-thin-router-pattern-c10)
- [Quarantine worked examples (C11)](#quarantine-worked-examples-c11)

## The three load levels

Treat each level as a hard design target, not a guideline. The agent platform loads
each level at a different moment, so a fact in the wrong level either burns context that
is always present or never arrives when needed. [C1]

| Level | What lives here | Budget | When it loads |
|-------|-----------------|--------|---------------|
| Metadata | `name` + `description` frontmatter | ~100 tokens | Always, for every skill in the catalog |
| Body | `SKILL.md` after the frontmatter | under 5000 tokens / under 500 lines | On trigger (description matches the request) |
| Resources | files in `references/`, `scripts/`, `assets/` | unbounded | On demand (the body points to them, or the agent runs them) |

Consequences that drive every other rule in this file:

1. Metadata is paid for on every request, so the description earns its ~100 tokens by
   triggering correctly and nothing more. Authoring rules for the description live in
   `skills.md`.
2. Body tokens are paid for only when the skill fires, but then they are paid in full.
   Keep the body to the non-skippable rules plus routing. Push how-to down to resources.
3. Resource tokens are paid for only when the agent reaches the file. This is where
   depth, variants, and worked examples belong.

## When to split the body into references

Split when the body approaches the budget or carries material the agent does not need on
every run. Move out first, in this order: advanced cases, variant paths, long worked
examples, deep domain background. Keep inline only the core workflow plus the selection
guidance that tells the agent which path or reference to take. [C2]

Move to `references/`:

- Detailed procedures the agent needs only for one task shape.
- Advanced or edge-case handling most runs never hit.
- Variant flows (one file per variant) so the common path stays short.
- Long examples and tables that document rather than instruct.

Keep in the body:

- The non-skippable rules (the ones an agent must not get wrong even if it never opens a
  reference).
- The routing table that maps a request shape to the right reference.
- Selection guidance: how to choose between the references and paths on offer.

## Bucket selection: scripts vs references vs assets

Choose the bucket by how the file touches the context window, not by file type. [C3]

| Bucket | Relationship to context | Use for |
|--------|-------------------------|---------|
| `scripts/` | Executed, not read. Output enters context, the source does not. | Deterministic logic the agent would otherwise re-derive each run: validators, generators, formatters. See `scripts.md`. |
| `references/` | Read only when the body points the agent to it. | Depth, procedures, variants, examples that instruct. |
| `assets/` | Copied into output, never read into context. | Templates, boilerplate, fixtures the agent emits or copies verbatim. |

Decision rule: if the content is logic that runs, put it in `scripts/` and document the
interface (`--help`, exit codes) rather than the implementation. If it is knowledge the
agent reads to decide or act, put it in `references/`. If it is bytes the agent copies
into its output without reading, put it in `assets/`.

## Reference-link discipline (C4)

Bind every reference link to an observable trigger: a condition the agent can check
against the request or the run state. Never ship a bare "see references/ for more". A
bare pointer makes loading a judgment call, so the agent either loads everything (burning
the budget the split was meant to save) or loads nothing (and acts blind). [C4]

| Form | Verdict |
|------|---------|
| `Read references/hooks.md when authoring a lifecycle hook.` | Good. Trigger is the task shape. |
| `Read references/errors.md when the API returns a non-200 status.` | Good. Trigger is observable run state. |
| `See references/ for more detail.` | Bad. No trigger; loading is a guess. |
| `Refer to the references as needed.` | Bad. "As needed" is not a condition. |

Write the trigger as the request shape the agent can match ("when authoring an agent",
"when the user names a hook event") or a run-state signal it can read ("when the test
suite reports a failure", "when the frontmatter validator exits non-zero").

## One level deep, with a table of contents (C5, C6)

Keep every reference exactly one level deep from `SKILL.md`: the body links to
`references/x.md`, and `references/x.md` does not link onward to a further file the agent
must chase. Nested references get head-previewed by the platform, so the agent acts on a
partial read and misses content below the preview window. Flatten instead: if a reference
grows a second level, split it into sibling files the body routes to directly. [C5]

Add a table of contents to the top of any reference over 100 lines so the agent can jump
to the relevant section instead of reading linearly. For very large files, put grep
patterns in the body so the agent can locate a section without loading the whole file.
[C6]

## Store each fact once (C7)

Keep each fact in exactly one place. Do not restate a rule across the body and a
reference, across two references, or across two skills. Duplicated doctrine drifts: one
copy gets updated, the other goes stale, and the agent cannot tell which is current. When
two files need the same fact, one owns it and the other points to the owner.

This file owns the load-level model. The body and the other references point here for it
and do not repeat the table or the budgets. [C7]

## Cross-reference other skills by name (C8)

Name a required companion skill with a requirement marker, not a path. Use a line the
agent reads as a dependency it loads on its own terms. [C8]

| Form | Effect |
|------|--------|
| `REQUIRED BACKGROUND: superpowers:test-driven-development` | Good. Names the dependency; the agent loads it when relevant. |
| `For eval depth, use plastic-evaluating-skills.` | Good. Names the skill, leaves loading to the agent. |
| `@skills/evaluating-skills/SKILL.md` | Bad. `@`-path syntax force-loads the file immediately, defeating disclosure. |

The `@`-path form pulls the target into context the moment the line is read, so it spends
the budget the level split was built to protect. Name the skill and let the trigger
decide when it loads.

## Ship only what does the job (C9)

Ship the SKILL.md, the references the body routes to, the scripts it runs, and the assets
it copies. Nothing else. No README, CHANGELOG, or QUICK_REFERENCE inside a skill: the
description is the skill's front door, and a second front door duplicates it (C7) and adds
files the agent must skip past. No orphan files (a file no link points to and no script
runs). If nothing reaches a file, delete it. [C9]

## The thin-router pattern (C10)

For a knowledge-heavy domain (one with many distinct request shapes, each needing
different depth), make the body a thin router: a short header of non-skippable rules plus
a table that maps a request shape to the one reference that handles it. The body inlines
no how-to. It decides which reference to load and stops. [C10]

Router body shape:

```
# skill-name

<non-skippable rules: the few facts an agent must not get wrong>

## Routing

| When the task is... | Read |
|---------------------|------|
| authoring an Agent Skill | references/skills.md |
| authoring a subagent     | references/agents.md |
| authoring a lifecycle hook | references/hooks.md |
```

The router keeps the always-paid body cost flat as the domain grows: adding a new request
shape adds one reference and one table row, not more body. Each reference stays focused on
its one shape.

## Quarantine worked examples (C11)

Keep the maxim in context, keep the example out of it. State the rule in the body or the
reference; move long worked examples to a file the agent loads only when it needs to see
the rule applied. An example is illustration, not instruction: it is paid for on every run
if it sits in the body, but it is needed only when the rule alone is not enough. Put the
short rule where it triggers, and route to the example with a trigger condition (C4). [C11]
