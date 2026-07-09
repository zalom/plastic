---
name: plastic-skill-creating
description: >
  Author or revise a Plastic skill, a subagent or Agent role file, or a
  lifecycle hook with progressive disclosure. Use when creating or editing a
  SKILL.md, writing a description or frontmatter, designing the slim body,
  building references, evals, or scripts, or scaffolding a new skill. Also use
  when a skill is too big or over its token budget, when prompts are bloated,
  when an agent keeps missing a step or ignoring instructions, or when the user
  says "progressive disclosure", "write a skill", "thin router", "split into
  references", or "make this slim".
user-invocable: true
---

# Creating Skills

Author skills, agents, and hooks as thin routers over deep references. This
body carries the rules that must stay correct without opening anything, then
routes each authoring task to the reference that holds the depth.

## Rules (must be right even if no reference is opened)

- Three load levels, hard budgets: metadata around 100 tokens (always loaded),
  body under 5000 tokens and under 500 lines (loaded on trigger), references on
  demand. Keep the body well under budget, not at the ceiling.
- Progressive disclosure first: the body routes, the references hold the depth.
  Any deep how-to in the body belongs in a reference instead.
- Description states WHEN to use, not the workflow. Write it in third person,
  front-load concrete trigger keywords, and include at least one indirect
  trigger (a request that never names the domain). Never summarize the steps.
- Bind every reference link to an observable trigger condition. Never leave a
  bare pointer to a reference.
- References stay one level deep. Any reference over 100 lines opens with a
  table of contents.
- Build at least three evals before writing extensive docs.
- Match determinism to fragility: a deterministic script for fragile or
  repeated mechanical steps, prose for judgment calls.
- Imperative voice, no second person. No em-dashes or en-dashes in any shipped
  skill or doc (use commas, periods, parentheses, colons).

## Route the authoring task to its reference

| Authoring task | Open |
|---|---|
| Starting any authoring task: load the load-level model and the thin-router pattern first | `references/progressive-disclosure.md` |
| Authoring an Agent Skill (frontmatter, description, slim body, voice) | `references/skills.md` |
| Authoring a subagent or Agent role file | `references/agents.md` |
| Authoring a lifecycle hook | `references/hooks.md` |
| Deciding script versus prose, or writing a script | `references/scripts.md` |
| Building evals for a skill | `references/evals.md` |

## Shrink context, or let a skill self-improve

- When prompts or tool output blow the context budget, open `references/hooks.md` (E7) for
  the global token levers: a PostToolUse hook that trims noisy tool output before it enters
  context, and Programmatic Tool Calling that keeps looped tool results in code, not context.
- When a skill should learn from its own real runs, open `references/hooks.md` (E8) for the
  propose-only Stop or SubagentStop loop (transcript to proposed edits to human approval to
  git, effort-gated). The dedicated skill is the future `improving-skills` skill.

## Scaffolder and evals

- To start a new skill, agent, or hook from a born-slim file, run
  `scripts/scaffold.rb`.
- To design, run, and grade evals in depth (paired runs, assertions after
  observing, pass rates), use the `plastic-skill-evaluating` skill.
