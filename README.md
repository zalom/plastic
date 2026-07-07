# Plastic

**Where you were, where you are, where you are heading.**

The everyday problem: losing the thread of your own work. You step away for a
day and come back to find the reasoning behind a decision is gone. A session
ends and the next one starts from nothing. Plastic keeps a durable, growing
record of your work as you do it, so that thread never breaks.

## Why Plastic

You do not write documentation about your work after the fact. You do the
work as an intent (a short file that states what you want, why, how you plan
to get there, and what happened). Because intents stay after you finish them,
and because they link to the intents that shaped them and the ones they led
to, they build into a queryable trace of your project over time. You can ask
what happened, why a choice was made, or where an idea came from, and get an
answer grounded in your own history. Memory is the result of working this
way, not a feature bolted onto an agent afterward.

## Two founding systems

**System for the Brain.** Plastic is built on the Zettelkasten method: small,
linked notes that add up to more than their sum. The name borrows from
neuroplasticity, the brain's own way of adapting and rewiring itself. An
intent is one such note. Its `sources` and `chain` links connect it to the
intents that shaped it and the ones it led to, so the store grows into a
graph you can actually navigate, not a pile of files.

**System for the Work.** Plastic separates the deterministic part of work
from the creative part. The blueprint (conventions, templates, directory
layout, and the lifecycle stages) is fixed: it comes out the same shape no
matter who or what is doing the work. The thinking (the actual reasoning
about what to build and how) stays free: a human or an agent does it, and
Plastic never replaces that judgment, only steers and checks it. This is
convention over configuration: one readable shape for every intent, so any
person or agent can pick up where another left off.

## The Two Cycles

**Coordinator loop (B→O→R):** Build → Observe → Repeat. The agent advances
the active intent, observes what the work surfaced, and repeats with the
next one. This loop runs continuously, across sessions.

**Intent lifecycle (W→W→H→E):** What → Why → How → Exec. Each intent moves
from capture through justification and planning to delivery. Intents produce
artifacts: `spec.md`, `plan.md`, `checklist.md`, `outcome.md`.

## How Plastic differs

Plastic is not a memory service. Tools like mem0 give an agent a vector
database to store and recall facts through an API; the memory lives in that
service, apart from your project. Plastic instead keeps intents as plain,
git-tracked Markdown files, moved through an enforced lifecycle (What, Why,
How, Exec) that a person can read without any tooling. The result reads like
the Zettelkasten linking model long used for personal notes, applied to
software delivery.

Projects like beads add persistent memory on top of an existing agent
workflow. Plastic shares that goal, an agent should remember what it did and
why, but gets there by making the intent itself, with its spec, plan, and
delivered outcome, the actual unit of work. Plastic runs today with Claude
Code, and works with Cursor and Cline through the same file-based
conventions.

## Install

Plastic requires Ruby (pre-installed on macOS and Linux) and Node.js 18 or
later.

Plastic is in beta. Install with:

```bash
npx @zalom/plastic@beta --claude
```

Replace `--claude` with `--codex` for Codex CLI, `--hermes` for Hermes, or
`--all` for all supported agents.

A stable channel will follow later:

```bash
# Stable (when available, general use)
npx @zalom/plastic --claude
```

The bare command above is not a working install yet. It currently resolves
to an early stub release, so use `@beta` for now.

Bun users can substitute `bunx` for `npx` (for example, `bunx
@zalom/plastic@beta --claude`). Bun is never required.

Skills install as flat, hyphen-namespaced personal skills (`plastic-doctor`,
`plastic-auto`, and so on). Invoke them with a hyphen. Plastic is **not** a
Claude Code plugin; re-running the installer automatically removes any
legacy plugin registration.

### Updating

From within your agent, say "update plastic" or run:

```bash
npx @zalom/plastic@beta --claude
```

The `plastic-update` command shows available versions across all channels
and lets you choose which to install.

## Quick Start

After installation, run `/clear` to load Plastic conventions, then:

1. Say "new intent" or run `/plastic-creating-intent` to create your first intent
2. Describe what you want to accomplish
3. Use `/plastic-brainstorming` to explore the design
4. Use `/plastic-writing-plans` to create an implementation plan
5. Use `/plastic-executing-plan` to deliver it

Guided delivery (a human at every gate) is the default. Say "auto" if you
want the agent to run the full lifecycle on its own instead.

Run `/plastic-dashboard` any time for a Value x Effort view across every
intent and what to work on next.

## Agents

Each lifecycle stage has one dispatchable background agent: `plastic-intent-discovery` for
What, `plastic-brainstorming` and `plastic-spec-specialist` for Why, `plastic-planner` for
How, `plastic-executor` for Exec, `plastic-intent-curator` for Done, plus `plastic-enforcer`
as the auto-mode orchestrator. Every agent pins an explicit Claude Code model alias (opus or
sonnet) in its frontmatter: never `inherit`, never Fable. See `docs/architecture.md` for the
stage table and `docs/internals.md` for how the model is configured, resolved, and applied at
install time.

## Documentation

- [`docs/architecture.md`](docs/architecture.md): system structure, the two
  processes, the store layout, and the component map.
- [`docs/internals.md`](docs/internals.md): how Plastic stays deterministic, the
  determinism breakdown, and the harness system.
- [`docs/guides/`](docs/guides/index.md): task-oriented guides, from your
  first intent in 10 minutes to picking a delivery mode.

## Conventions

Plastic conventions live in `PLASTIC.md`, distributed to `~/.plastic/PLASTIC.md`
and overwritten on every update. Project-specific rules live in `AGENTS.md`,
scaffolded once at `~/.plastic/AGENTS.md`. Run `plastic-doctor` to check
installation health.
`plastic-doctor --core` runs a binary install-integrity check (compares files
against the install manifests; pass or error). `plastic-doctor --store` checks
store state (intents, INDEX sections, conventions) and can be scoped to
`global` or a project slug. The full `plastic-doctor` runs all checks and is
run automatically after every update.

## License

MIT
