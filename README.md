# Plastic

[![npm version](https://img.shields.io/npm/v/@zalom/plastic/beta)](https://www.npmjs.com/package/@zalom/plastic)
[![npm downloads](https://img.shields.io/npm/dm/@zalom/plastic)](https://www.npmjs.com/package/@zalom/plastic)
[![license](https://img.shields.io/npm/l/@zalom/plastic)](LICENSE)
[![CI](https://github.com/zalom/plastic/actions/workflows/test.yml/badge.svg)](https://github.com/zalom/plastic/actions/workflows/test.yml)

**Where you were, where you are, where you are heading.**

The everyday problem is losing the thread of your own work. You step away
for a day, come back, and the reasoning behind a decision is gone. Plastic
keeps a durable record of your work as you make it, so the thread never
breaks. Read [why I built it](MANIFESTO.md).

Paste this to your coding agent to start:

```
Install Plastic: run `npx @zalom/plastic@beta --claude`.
Then run `/clear` and say "new intent" to begin.
Drive the work through What, Why, How, and Exec, and let Plastic
keep the record as we go.
```

## Install

Plastic needs Ruby (already on macOS and Linux) and Node.js 18 or later.

Plastic is in beta. Install with:

```bash
npx @zalom/plastic@beta --claude
```

Swap `--claude` for `--codex`, `--hermes`, or `--all` to match your agent.
Bun users can run `bunx` in place of `npx`; Bun is never required. To update
later, say "update plastic" or run the same `@beta` command again.

A stable channel will follow. The bare command below is not a working
install yet. It resolves to an early stub release, so keep `@beta` for now.

```bash
npx @zalom/plastic --claude
```

Skills install as flat, hyphen-namespaced personal skills (`plastic-doctor`,
`plastic-auto`, and so on). Invoke them with a hyphen. Plastic is not a
Claude Code plugin; re-running the installer removes any legacy plugin
registration.

## The lost thread

You do the work as an intent: a short file that states what you want, why,
how you plan to get there, and what happened. Intents stay after you finish,
and link to the ones that shaped them and the ones they led to, so your
project builds into a record you can ask questions against.

Come back after a day and ask where you were:

```
You:   Where was I?
Agent: Last intent: 140, "README round two". The plan is written and
       approved. Next step is the ships-itself proof block. Want me to
       pick it up in auto?
```

Memory is the result of working this way, not a feature bolted onto an agent
afterward.

## Quick Start

After installation, run `/clear` to load Plastic conventions, then:

1. Say "new intent" to create your first piece of work
2. Describe what you want, in plain words
3. Explore the design, write a plan, then deliver it, one stage at a time

Guided delivery (a human at every gate) is the default. Say "auto" to let
the agent run the full lifecycle on its own. Run `/plastic-dashboard` any
time for a Value x Effort view of every intent and what to do next.

<details>
<summary>See the full 10-minute walkthrough</summary>

1. Install once: `npx @zalom/plastic@beta --claude`.
2. Describe a small first task, like "add a `--version` flag." Plastic
   scaffolds the intent file for you; never write it by hand.
3. Board it: say "continue." Plastic takes a lock, then asks "auto or guided?"
4. Say "auto." The agent runs Why, then How, then Exec in one pass, then
   writes `outcome.md` with exactly what was delivered and moves the intent
   to Completed.

Full guide: [your first intent in 10 minutes](docs/guides/your-first-intent-in-10-minutes.md).
</details>

## Two founding systems

**System for the Brain.** Plastic is built on the Zettelkasten method:
small, linked notes that add up to more than their sum. The name borrows
from neuroplasticity, the brain's own way of rewiring itself. An intent is
one such note. Its `sources` and `chain` links connect it to the intents
that shaped it and the ones it led to, so the store grows into a graph you
can navigate, not a pile of files.

**System for the Work.** Plastic separates the fixed part of work from the
creative part. The blueprint (conventions, templates, layout, and the
lifecycle stages) comes out the same shape no matter who does the work. The
thinking (what to build and how) stays free: a human or an agent does it,
and Plastic steers and checks that judgment without replacing it. One
readable shape for every intent, so any person or agent can pick up where
another left off.

## Plastic ships itself

Every release of Plastic is a set of intents that Plastic itself tracked,
planned, and delivered. Over 2026-07-06 and 2026-07-07, the stable-1.0
roadmap run cut six beta releases, beta.32 through beta.37, collecting 19
intents. The evidence is public in `CHANGELOG.md` and the roadmap:

```
- `1.0.0-beta.19` - shipped 2026-06-25; collected 92 (plastic-humanizer skill: clean authored prose, remove AI tells and slop from docs/specs/outcomes/READMEs).
- `1.0.0-beta.3` - shipped; collected 74 (mandatory structured agent completion reports + deterministic fallback).
- [x] 129 First-run user guides — delivered
- [x] 109 Audit README against the PLASTIC implementation — delivered
- [x] 97 Implement the first-sight positioning (README + repo) — delivered
```

No other memory tool can paste this, because none is built with itself.

## How Plastic differs

Plastic is not a memory service. Tools like mem0 give an agent a vector
database to store and recall facts through an API, and that memory lives in
the service, apart from your project. Plastic keeps intents as plain,
git-tracked Markdown files, moved through an enforced lifecycle (What, Why,
How, Exec) that a person can read without any tooling.

Projects like beads add persistent memory on top of an existing agent
workflow. Plastic shares that goal but makes the intent itself, with its
spec, plan, and delivered outcome, the unit of work. It runs today with
Claude Code, and works with Cursor and Cline through the same conventions.

## Documentation

Each lifecycle stage has one dispatchable background agent, from discovery
through delivery, plus `plastic-enforcer` as the auto-mode orchestrator.

- [`docs/architecture.md`](docs/architecture.md): system structure, the two
  processes, the store layout, the component map, and the full stage table.
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

Claude Code is powerful. Plastic makes it remember.
