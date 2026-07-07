# Plastic

> **Alpha software.** Expect breaking changes between releases.
> Install: `npx @zalom/plastic@alpha --claude`

Intent-driven idea development system for AI coding agents. Named after
**neuroplasticity**: adaptive, malleable, dynamic, resilient.

Plastic thinks in **intents**, not tasks. An intent is a desire, something
you want to accomplish, explore, or understand. Intents are atomic thoughts
that get developed through two nested processes.

## The Two Cycles

**Coordinator loop (B→O→R):** Build → Observe → Repeat. The agent advances the
active intent, observes what the work surfaced, and repeats with the next one.
This loop runs continuously across sessions.

**Intent lifecycle (W→W→H→E):** What → Why → How → Execute. Each intent moves
from capture through justification and planning to delivery. Intents produce
artifacts: `spec.md`, `plan.md`, `checklist.md`, `outcome.md`.

## How Plastic Works

Plastic is a **thinking system**, a blueprint for taking a desire from intent to
delivery. It splits the work in two:

- **The blueprint (deterministic).** The conventions, templates, directory structure,
  lifecycle, and linking rules. This is *how to fill in the work*, and it comes out
  identically no matter who or what is working.
- **The brain (non-deterministic).** The human or LLM that does the actual thinking.
  Plastic never replaces it. It only **steers and validates** it.

Determinism lives in the **form** of the work (section sets, ordering, schemas, naming,
IDs, file layout), never in the brain's reasoning. The framework stays constant while the
thinking varies. Run Plastic on Claude Code, Codex, Hermes, OpenClaw, or by hand on paper
in Obsidian or Word, and the only thing that changes is the *quality of thought*. The
proof is the paper test: if a person with no tooling and no AI can reproduce a
correctly-shaped intent, the determinism is in the form, not the agent.

**Deterministic by design, free by intent.** The rigid part is rigid on purpose. It is
what makes work portable, reviewable, and resumable across any agent. The free part is
free on purpose. It is where the brain's creativity lives. Plastic draws the line between
the two and holds it.

**Harnesses are how it holds the line.** Shared harnesses (conventions, templates, and
directory structure) constrain humans and agents alike. Agent-extra harnesses (evals that
check a skill's output, plus hooks and instructions that steer reasoning) give an agent
the instincts a careful person already has: stop and save state, leave a note when the
context runs out, never plan before specifying.

This is **intent-driven delivery**, a new shape for the software lifecycle in the age of
agentic engineering. The unit of work is an *intent*, not a ticket, and every intent
carries its own spec, plan, checklist, and outcome as it moves through What, Why, How, and
Execute. What you get is agent-agnostic, auditable, and additive: a knowledge graph of
*why* things were built, not just what.

## Install

Plastic requires Ruby (pre-installed on macOS/Linux) and Node.js 18+.

```bash
# Alpha (current, active development)
npx @zalom/plastic@alpha --claude

# Beta (when available, API-stable, bug hunting)
npx @zalom/plastic@beta --claude

# Stable (when available, general use)
npx @zalom/plastic --claude
```

Replace `--claude` with `--codex` for Codex CLI, `--hermes` for Hermes, or
`--all` for all supported agents.

Bun users can substitute `bunx` for `npx` (e.g. `bunx @zalom/plastic@alpha --claude`).
Bun is never required.

Skills install as flat, hyphen-namespaced personal skills (`plastic-doctor`,
`plastic-auto`, and so on). Invoke them with a hyphen. Plastic is **not** a Claude Code
plugin; re-running the installer auto-removes any legacy plugin registration.

### Updating

From within your agent, say "update plastic" or run:

```bash
npx @zalom/plastic@alpha --claude
```

The `plastic-update` command shows available versions across all channels and
lets you choose which to install.

## Quick Start

After installation, run `/clear` to load Plastic conventions, then:

1. Say "new intent" or run `/plastic-creating-intent` to create your first intent
2. Describe what you want to accomplish
3. Use `/plastic-brainstorming` to explore the design
4. Use `/plastic-writing-plans` to create an implementation plan
5. Use `/plastic-executing-plan` to deliver it

Or say "auto" to let the agent handle the full lifecycle autonomously.

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
