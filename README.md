# Plastic

[![npm version](https://img.shields.io/npm/v/@zalom/plastic/beta)](https://www.npmjs.com/package/@zalom/plastic)
[![npm downloads](https://img.shields.io/npm/dm/@zalom/plastic)](https://www.npmjs.com/package/@zalom/plastic)
[![license](https://img.shields.io/npm/l/@zalom/plastic)](LICENSE)
[![CI](https://github.com/zalom/plastic/actions/workflows/test.yml/badge.svg)](https://github.com/zalom/plastic/actions/workflows/test.yml)

## Intent-based idea development for AI-assisted work.

Turn an idea into a durable intent: explore it, make decisions,
plan it, deliver it, and keep the reasoning, even when the model,
agent, session, or your own thinking changes.

[Install](#start-in-60-seconds) [See it work](#built-in-plastic) [Read the manifesto](MANIFESTO.md)

**Develop ideas with intent. Build with any brain.**

Install Plastic (beta):

```bash
npx @zalom/plastic@beta --claude
```

Paste this to your coding agent to start:

```
Install Plastic: run `npx @zalom/plastic@beta --claude`.
Then run `/clear` and say "new intent" to begin.
Drive the work through What, Why, How, and Exec, and let Plastic
keep the record as we go.
```

## Why Plastic?

**Plastic gives changing minds a durable way to develop ideas into work.**

Your thinking changes. The work should not reset.
New information changes the problem.
A better model changes the approach.
A different agent changes the way work gets done.
You may change your mind entirely.

Plastic is named after neuroplasticity: the ability to adapt
without starting from nothing.

Plastic keeps the shape of the work stable:

- one durable intent
- one visible lifecycle
- one place for context, decisions, plans, and outcomes
- links between the ideas that shaped the work and the ideas it creates

The human or model is free to think.
Plastic makes that thinking legible, resumable, and useful later.

Plastic is built for an AI-native developer, technical founder, or
independent builder who works across multiple sessions, has ideas before
they have tickets, and feels the cost of losing reasoning between agents,
contexts, and days.

It solves problems that builder already feels:

- "I do not need another TODO list."
- "I do not want my work trapped inside a chat."
- "I want to explore without losing the decision trail."
- "I want a better model or new agent to inherit the work, not restart it."
- "I want my ideas to compound."

## Start in 60 seconds

One command installs Plastic for your agent:

```bash
npx @zalom/plastic@beta --claude
```

Then load the conventions and begin:

```text
/clear
new intent
```

Describe what you want in plain words, like "add a `--version` flag." Plastic
scaffolds the intent and walks it through What, Why, How, and Exec. For the
full path, read [your first intent in 10 minutes](docs/guides/your-first-intent-in-10-minutes.md).

## Intent is the main unit of work in Plastic

A task assumes you already know the work.

An intent begins earlier:
something you want to accomplish, explore, or understand.

Plastic helps you develop it until it becomes a decision,
a plan, a delivery, and a reusable piece of project history.

## Plastic is not just

Agent memory that remembers facts.
Task tracker that remembers work items.
Spec that remembers what to build.

## Plastic is all of that

Plastic remembers how an idea developed:
what you wanted, why it mattered, what changed,
what you decided, and what happened next.

## How an intent develops

An intent moves through four stages. Each one has a plain question and leaves
a durable artifact behind.

| Stage | Plain meaning | Durable artifact |
|---|---|---|
| What | What are we trying to make, learn, or change? | Intent |
| Why | What context, evidence, and decisions shape it? | Specification |
| How | What is the plan? | Plan and checklist |
| Exec | What was actually delivered? | Outcome |

## Compatibility and ownership

- Native installers for Claude, Codex, Hermes, and all supported targets.
- Plain Markdown plus Git. The work stays in files you own.
- Personal stores by default.
- Guided delivery with a human at every gate, or autonomous delivery when you
  ask for it.
- Beta status.

Plastic needs Ruby (already on macOS and Linux) and Node.js 18 or later. Swap
`--claude` for `--codex`, `--hermes`, or `--all` to match your agent. Bun
users can run `bunx` in place of `npx`; Bun is never required.

A stable channel will follow. The bare `npx @zalom/plastic` command is not a
working install yet. It resolves to an early stub release, so keep `@beta`
for now.

## Built in Plastic

Plastic is developed through Plastic.

The roadmap, intent history, plans, decisions, and outcomes
behind releases are part of the repository, not a hidden process.

See the current [roadmap](ROADMAP.md) and [changelog](CHANGELOG.md).

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
