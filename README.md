# Plastic

[![npm version](https://img.shields.io/npm/v/@zalom/plastic)](https://www.npmjs.com/package/@zalom/plastic)
[![npm downloads](https://img.shields.io/npm/dm/@zalom/plastic)](https://www.npmjs.com/package/@zalom/plastic)
[![license](https://img.shields.io/npm/l/@zalom/plastic)](LICENSE)
[![CI](https://github.com/zalom/plastic/actions/workflows/test.yml/badge.svg)](https://github.com/zalom/plastic/actions/workflows/test.yml)

## Intent-based idea development system for AI-assisted work.

> Plastic is a system that turns an intent, a vague goal or idea into a durable, linked record of discovery, decisions, delivery, and outcomes - it serves as a physical brain for your intents.

[[Install]](#start-in-60-seconds) [[See it work]](#built-with-plastic) [[Read the manifesto]](MANIFESTO.md)


## Why Plastic?

You do not always start with a task.

You start with an intent, something like:

> “I want users who are locked out to recover access safely.”

Plastic delivers this intent in successive stages: What -> Why -> How -> Exec.

The result is a readable, linked record of how an idea became real.

**Plastic gives changing minds a durable way to develop ideas into work.**

Plastic is named after neuroplasticity: the brain's amazing ability to change and adapt. It rewires itself as you learn new things, form memories, or heal from injuries. Instead of being fixed like a computer, your brain is more like clay. It constantly reshapes itself based on your experiences.

### What Plastic does?

Plastic keeps the shape of the work stable - **deterministic** work system:
- one durable intent
- one visible lifecycle
- one place for context, decisions, plans, and outcomes
- links between the ideas that shaped the work and the ideas it creates

Plastic leaves the human or AI model free to think - **non-deterministic** thinking system.

Plastic makes that thinking legible, resumable, and useful later.

## Who is Plastic for?

**Plastic is built for an AI-native developer, technical founder, or
independent builder who works across multiple sessions, has ideas before
they have intents, and feels the cost of losing reasoning between agents,
contexts, and days.**

## What it solves?

It solves problems that builder already feels:

- "I want to keep a record of my work - what I worked on, why I worked on it, how it was built"
- "I do not need another TODO list."
- "I do not want my work trapped inside a chat."
- "I want to explore without losing the decision trail."
- "I want a better model or new agent to inherit the work, not restart it."
- "I want my ideas to compound."

## Start in 60 seconds

One command installs Plastic for your agent:

```bash
npx @zalom/plastic --claude
```

Then load the conventions and begin:

```bash
/clear

I would like to learn more about Plastic and how it works.
```

Describe what you want in plain words, like "add a `--version` flag." Plastic
scaffolds the intent and walks it through What, Why, How, and Exec. For the
full path, read [your first intent in 10 minutes](docs/guides/your-first-intent-in-10-minutes.md).

## How Plastic works?

A task assumes you already know the work.

An intent begins earlier:
something you want to accomplish, explore, or understand.

Plastic helps you develop it until it becomes a decision,
a plan, a delivery, and a reusable piece of project history.

### Register What and start with Why

Plastic delivers all work through successive stages ->

| Stage | Meaning                                         | Developed concept  | On-disk artifact (evidence)                    |
| ----- | ----------------------------------------------- | ------------------ | ---------------------------------------------- |
| What  | What is the intention?                          | Intent             | {id}--slug.md                                  |
| Why   | What context, evidence, and decisions shape it? | Specification      | spec.md                                        |
| How   | What is the plan?                               | Plan and checklist | plan.md, checklist.md, actions/ACTION_1.md ... ACTION_N.md |
| Exec  | What was actually delivered?                    | Outcome            | outcome.md                                     |

## How to use Plastic

Plastic organizes all work as intents. Each intent is one directory, and it carries the same
small set of files at every stage.

**The intent directory**

| File | What it holds |
| ---- | -------------- |
| `{id}--slug.md` | The intent itself: intent line, context, decisions |
| `spec.md` | The Why, consolidated into one contract for the plan |
| `plan.md`, `checklist.md`, `actions/` | The How: the plan and its execution registry |
| `outcome.md` | The Exec record: what actually shipped |

See [`docs/architecture.md`](docs/architecture.md) for the full store layout, and
[reading a delivered intent](docs/guides/reading-a-delivered-intent.md) for how to read a
finished one fast.

**From idea to delivery, one line per stage**

| Stage | What happens |
| ----- | ------------- |
| What | Describe the idea in plain words; Plastic scaffolds the intent |
| Why | Explore it, one ruling at a time, then consolidate into `spec.md` |
| How | Turn `spec.md` into `plan.md` and `checklist.md` |
| Exec | Build the change, verify it, tick the checklist |
| Done | `outcome.md` records what shipped; the index moves the intent to Completed |

Walk this once in
[your first intent in 10 minutes](docs/guides/your-first-intent-in-10-minutes.md), or run
`plastic-tutorial` for an interactive, hands-on walkthrough of three different ways to work.

**Commands, by family**

| Family | Commands |
| ------ | -------- |
| Mode | `plastic-tutorial`, `plastic-auto` |
| Intent | `plastic-continuing`, `plastic-intent-creating`, `plastic-intent-starting`, `plastic-intent-brainstorming`, `plastic-intent-grilling`, `plastic-intent-speccing`, `plastic-intent-planning`, `plastic-intent-executing`, `plastic-intent-ending`, `plastic-intent-continuing`, `plastic-intent-researching` |
| Project and delivery | `plastic-project-creating`, `plastic-project-continuing`, `plastic-roadmap`, `plastic-roadmap-continuing`, `plastic-releasing` |
| Skill | `plastic-skill-creating`, `plastic-skill-evaluating` |
| Product | `plastic-install`, `plastic-update`, `plastic-uninstall`, `plastic-rollback`, `plastic-doctor`, `plastic-humanizer` |

See [`docs/guides/index.md`](docs/guides/index.md) for task-oriented walkthroughs.

The agent helps most at Why and How: turning a rough idea into rulings, and rulings into a
plan a machine can build from exactly. Read
[pick your mode](docs/guides/pick-your-mode.md) to decide how much of that to hand over.

## Compatibility and ownership

- Native installers for Claude (Codex, Hermes, and and others coming soon).
- Plain Markdown plus Git. The work stays in files you own.
- Personal stores by default.
- Guided delivery with a human at every gate, or autonomous delivery when you
  ask for it.
- An Opus main session auto-loads an Operating Manual for reasoning discipline, detected
  from the session's model with no setup required. A plastic-advisor agent ships
  alongside it for tiered expert consultations (state S, M, or L in the brief); which
  model runs the advisor is a choice made at install (Opus 4.8 or Fable 5, fable by
  default), never a hard-wired vendor pin.

Plastic needs Ruby (already on macOS and Linux) and Node.js 18 or later. Bun
users can run `bunx` in place of `npx`; Bun is never required.

## Built with Plastic

Plastic is developed through Plastic.

The roadmap, intent history, plans, decisions, and outcomes
behind releases are part of the repository, not a hidden process.

[changelog](CHANGELOG.md).

## Documentation

- [`docs/architecture.md`](docs/architecture.md): system structure, the two
  processes, the store layout, and the full stage table.
- [`docs/internals.md`](docs/internals.md): how Plastic stays deterministic
  and how the harness works.
- [`docs/guides/`](docs/guides/index.md): task-oriented guides, from your
  first intent in 10 minutes to picking a delivery mode.

## Conventions

Plastic conventions live in `PLASTIC.md`, distributed to `~/.plastic/PLASTIC.md`
and overwritten on every update. Project-specific rules live in `AGENTS.md`.
Run `plastic-doctor` to check installation health; it compares files against
the manifests, checks store state, and runs automatically after every update.

## License

MIT
