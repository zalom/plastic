# Authoring an Agent (subagent)

How to write a subagent / Agent role file: scope, tools, description, the reviewer pattern,
collector discipline, and the skill-vs-agent decision. Rules cite section D of the
best-practices standard (D1 through D6).

## Contents

- [When a skill suffices vs escalate to an agent](#when-a-skill-suffices-vs-escalate-to-an-agent)
- [The agent definition fields](#the-agent-definition-fields)
- [One focused task per agent](#one-focused-task-per-agent)
- [Tight tool set](#tight-tool-set)
- [Description: embedded when-to-use examples](#description-embedded-when-to-use-examples)
- [Collectors, not implementers](#collectors-not-implementers)
- [Reviewer / devil's-advocate agents](#reviewer--devils-advocate-agents)
- [Composing skills and agents](#composing-skills-and-agents)
- [Self-checks](#self-checks)

For load levels, the three-bucket model, and description-as-trigger rules, open
`progressive-disclosure.md` and `skills.md`. Do not re-derive them here (C7).

## When a skill suffices vs escalate to an agent

Decide before authoring an agent at all. A full agent carries its own context window and tool
grant, so it is too heavyweight for quick work [D5].

| Situation | Build | Why |
| --- | --- | --- |
| Light read-only check, single-file validation, scaffold one file | Skill | A skill loads on trigger and runs in the current context, no spin-up cost [D5] |
| Deep multi-file audit, parallel investigation, isolated noisy work | Agent | The isolated context keeps search and log noise off the main thread [D2][D5] |
| Same task repeated with deterministic steps | Script (see `scripts.md`) | Executed, not loaded; token-free and variance-free |

Default to a skill. Escalate to an agent only when the work needs an isolated context budget or
its own restricted tool grant.

## The agent definition fields

An agent file is frontmatter plus a system-prompt body. Set each field for one reason.

| Field | When it matters | Set it to |
| --- | --- | --- |
| `name` | Always. The orchestrator and `SendMessage` address the agent by it | Lowercase-hyphen, one capability (`spec-reviewer`, `dependency-auditor`) |
| `description` | Always. The orchestrator delegates purely on this text [D3] | Trigger conditions plus embedded when-to-use example pairs (see below) |
| `tools` | Always. Omitting it grants every tool, which over-arms the agent [D1] | Only the tools the one task needs |
| `model` | When the task is cheap (Haiku) or hard (Opus) | The cheapest tier that holds quality |
| `proactive` marker | When the agent should auto-fire without an explicit ask [D3] | Include "use proactively" inside the description |

Keep the body in imperative voice. State the agent's single job, its numbered process, and its
output contract. Push reference detail into files the agent reads on demand, same as a skill body.

## One focused task per agent

Give each agent exactly one task. Focused scope plus a tight tool set is what makes delegation
decidable and cheap [D1].

1. Name the single responsibility in one phrase. If the name needs "and", split into two agents.
2. Start with one agent. Add a specialist only when it materially improves isolation or tool
   scoping [D1]. More agents widen the discovery surface and the orchestrator's choice space.
3. Write the body around that one task. An agent that "reviews and also fixes and also reports" has
   three jobs and no clear output contract.

## Tight tool set

Grant only the tools the one task requires [D1].

| Agent kind | Typical tools | Excluded |
| --- | --- | --- |
| Reviewer / auditor | Read, Grep, Glob | Edit, Write, Bash (read-only by design) [D4] |
| Collector / researcher | Read, Grep, Glob, WebFetch | Edit, Write (returns a summary, does not change code) [D2] |
| Implementer | Read, Edit, Write, Bash | Only the surface its task touches |

A reviewer with Edit can rewrite the code it judges. A collector with Write can leak its noisy
context back into the tree. The tool list is the guardrail; keep it narrow.

## Description: embedded when-to-use examples

The orchestrator never reads the body at delegation time. It routes on the description alone, so
the description must teach the boundary by example [D3].

Write the description with:

1. A trigger clause in third person ("Use when reviewing a spec before the plan stage").
2. One or more `<example>` pairs showing a matching prompt, the assistant's choice to delegate, and
   a one-line `<commentary>` on why. Example pairs teach the boundary a keyword list cannot [D3].
3. "use proactively" when the agent should auto-fire without the user naming it [D3].

Concrete shape:

```
description: >
  Use when a spec is complete and needs an adversarial review before planning.
  Use proactively after the spec-specialist writes spec.md.
  <example>
    Context: spec.md just landed for the active intent.
    user: "Is this spec ready to plan?"
    assistant: "I'll use the spec-reviewer agent to challenge the spec before planning."
    <commentary>Adversarial review runs at the Why-to-How boundary.</commentary>
  </example>
```

A description that summarizes the agent's workflow instead of its trigger makes the orchestrator
act on the summary and skip the body. State when to fire, not how the agent works.

## Collectors, not implementers

Use a subagent as an information collector that returns a short summary, not as an implementer [D2].

| Do | Avoid |
| --- | --- |
| Return a tight summary: findings, file paths, a verdict | Stuffing raw search output or full file dumps back into the main thread |
| Write a plan or summary markdown file as shared memory; have the main thread read it [D2] | Passing large results inline, which defeats the isolation |
| Keep search, log, and crawl noise inside the agent's own context [D2] | Re-emitting that noise to the orchestrator |

The reason a subagent has an isolated context is to absorb noise. The filesystem (a plan or summary
file) is the shared memory between agents; the agent's return value is the headline, not the
transcript [D2].

## Reviewer / devil's-advocate agents

A reviewer agent needs four things, or it produces unscoped, unverifiable results [D4].

1. Read-only tools: Read, Grep, Glob, and nothing that edits [D4]. A reviewer that can edit stops
   being a reviewer.
2. A numbered review process in the body, so every run covers the same checks in the same order.
3. Explicit anti-scope: a "do not use for" clause that names what the agent must not do (implement
   fixes, refactor, approve its own changes) [D4].
4. A fixed, severity-bucketed output format, so findings are comparable across runs [D4].

Fixed output contract:

```
## Critical
- <finding> (file:line) -> <why it blocks>

## Major
- <finding> (file:line) -> <impact>

## Minor
- <finding> (file:line) -> <suggestion>

## Verdict
PASS | BLOCK, with one-line reason.
```

The severity buckets and the verdict are mandatory. Empty buckets stay in, marked "none", so a
reader can tell the agent checked.

## Composing skills and agents

Two mechanisms load content into an agent's context. Choose by what budget the isolated agent
should carry [D6].

| Mechanism | Effect | Use when |
| --- | --- | --- |
| Subagent `skills:` | Preloads the full skill content into the agent at spawn [D6] | The agent must always have that skill's rules in hand |
| Skill `context: fork` | Runs the skill body as a task prompt inside a chosen agent type [D6] | A skill should execute as an isolated agent, not inline |

Pick deliberately. `skills:` spends the agent's budget up front for guaranteed availability;
`context: fork` hands the body to a fresh agent so the work runs isolated [D6].

## Self-checks

- Could this be a skill instead? If the work is light or single-file, build a skill [D5].
- Does the agent have exactly one job, named without "and"? [D1]
- Is the tool list the minimum the job needs, and read-only for a reviewer? [D1][D4]
- Does the description carry at least one `<example>` pair and "use proactively" if it auto-fires? [D3]
- Does the agent return a summary and use a file as shared memory, not dump its context? [D2]
- Does a reviewer have a numbered process, an anti-scope clause, and a severity-bucketed output? [D4]
