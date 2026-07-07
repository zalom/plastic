# Plastic

[![npm version](https://img.shields.io/npm/v/@zalom/plastic/beta)](https://www.npmjs.com/package/@zalom/plastic)
[![npm downloads](https://img.shields.io/npm/dm/@zalom/plastic)](https://www.npmjs.com/package/@zalom/plastic)
[![license](https://img.shields.io/npm/l/@zalom/plastic)](LICENSE)
[![CI](https://github.com/zalom/plastic/actions/workflows/test.yml/badge.svg)](https://github.com/zalom/plastic/actions/workflows/test.yml)

**Plastic is an intent-based idea development system for AI-assisted work.**

It turns an intent into a durable, linked record of discovery, decisions,
delivery, and outcomes, so work can keep moving even when the model, agent,
session, or implementation changes. Read [why I built it](MANIFESTO.md).

**Fixed rails. Flexible thinking.**

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

One idea, from a sentence to a delivered outcome:

```text
"I want to make account recovery safer."
          ↓
new intent
          ↓
Why → How → Exec
          ↓
Outcome recorded
          ↓
Next day: "Where was I?"
```

Where you were. Where you are. Where the idea is going.

## Start with an intent, not a ticket

A task assumes you already know the work.

An intent begins earlier: something you want to accomplish, explore, or
understand. Plastic helps you develop it until it becomes a decision, a plan,
a delivery, and a reusable piece of project history.

## Plastic is not another memory layer

Agent memory remembers facts. Task trackers remember work items. Specs
remember what to build.

Plastic remembers how an idea developed: what you wanted, why it mattered,
what changed, what you decided, and what happened next.

The framing is complementary, not competitive. Use Plastic to develop and
preserve intent. Use your coding agent, issue tracker, planner, and
repository to execute it.

## How an intent develops

An intent moves through four stages. Each one has a plain question and leaves
a durable artifact behind.

| Stage | Plain meaning | Durable artifact |
|---|---|---|
| What | What are we trying to make, learn, or change? | Intent |
| Why | What context, evidence, and decisions shape it? | Specification |
| How | What is the plan? | Plan and checklist |
| Exec | What was actually delivered? | Outcome |

## Fixed rails. Flexible thinking.

New information changes the problem. A better model changes the approach. A
different agent changes the way work gets done. You may change your mind
entirely. Plastic is named after neuroplasticity: the brain's ability to
adapt without starting from nothing.

Plastic keeps the shape of the work stable, and leaves the thinking free. A
human or a model does the reasoning; Plastic steers and checks that judgment
without replacing it, so the thinking stays legible, resumable, and useful
later.

| Plastic keeps stable | Humans and models keep flexible |
|---|---|
| lifecycle | exploration |
| file structure | reasoning |
| links and provenance | decisions |
| gates and savepoints | implementation choices |
| outcome records | new insights |

Plastic also borrows from the Zettelkasten method: small linked notes that
add up to more than their sum. An intent is one such note. Its `sources` and
`chain` links connect it to the intents that shaped it and the ones it led
to, so the store grows into a graph you can navigate and ask questions
against as ideas evolve over time.

## The work survives change

The reasoning behind your work should not reset when the conditions do. Three
familiar moments show why it matters:

- You return after a day or a week.
- You switch from one agent or model to another.
- New evidence changes the original approach.

Because the intent holds the record, you can come back and ask where you
were:

```
You:   Where was I?
Agent: Last intent: 140, "README round two". The plan is written and
       approved. Next step is the ships-itself proof block. Want me to
       pick it up in auto?
```

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

Plastic is developed through Plastic. The intent history, plans, decisions,
and outcomes behind every release are part of this repository, not a hidden
process. See [`CHANGELOG.md`](CHANGELOG.md) for the shipped history.

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

Plastic gives changing minds a durable way to develop ideas into work.
