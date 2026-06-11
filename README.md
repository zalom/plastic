# Plastic

> **Alpha software.** Expect breaking changes between releases.
> Install: `npx @zalom/plastic@alpha --claude`

Intent-driven idea development system for AI coding agents. Named after
**neuroplasticity** — adaptive, malleable, dynamic, resilient.

Plastic thinks in **intents**, not tasks. An intent is a desire — something
you want to accomplish, explore, or understand. Intents are atomic thoughts
that get developed through two nested processes.

## The Two Cycles

**Coordinator loop (B→O→R):** Brainstorm → Organize → Review. The human and
agent explore ideas, structure them into intents, and validate the results.
This loop runs continuously across sessions.

**Intent lifecycle (W→W→H→E):** Why → What → How → Execute. Each intent moves
from motivation through specification, planning, to delivery. Intents produce
artifacts: `spec.md`, `plan.md`, `checklist.md`, `outcome.md`.

## Install

Plastic requires Ruby (pre-installed on macOS/Linux) and Node.js 18+.

```bash
# Alpha (current — active development)
npx @zalom/plastic@alpha --claude

# Beta (when available — API-stable, bug hunting)
npx @zalom/plastic@beta --claude

# Stable (when available — general use)
npx @zalom/plastic --claude
```

Replace `--claude` with `--codex` for Codex CLI, `--hermes` for Hermes, or
`--all` for all supported agents.

Bun users can substitute `bunx` for `npx` (e.g. `bunx @zalom/plastic@alpha --claude`).
Bun is never required.

Skills install as flat, hyphen-namespaced personal skills (`plastic-doctor`,
`plastic-auto`, …) — invoke them with a hyphen. Plastic is **not** a Claude Code
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

## Conventions

All conventions live in `AGENTS.md`, distributed to `~/.plastic/AGENTS.md`
during installation. Run `plastic-doctor` to check installation health.

## License

MIT
