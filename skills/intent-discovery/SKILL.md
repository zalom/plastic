---
name: plastic-intent-discovery
description: >-
  What-stage context deposit at intent activation: run QMD discovery over the
  intent's chain/sources and related parked intents, and write findings to
  resources/discovery--<slug>.md for the Why stage to consume. Use when an intent
  is activated (moved from Future to Active), before the lock is armed and Why
  begins. Never writes the intent file itself.
---

# Intent Discovery — What-stage context deposit

Announce: "Discovering context for intent [ID] — [name]."

Runs once, at intent activation, before the lock and Why. It gathers what is
already known so Why does not start cold, and deposits it as a resource the
Why-stage brainstorming agent reads.

## When it fires
Inside `plastic-intent-starting`, at the moment the intent moves from
`## Future` to `## Active` (before the bridge is armed). Dispatched as the
`plastic-intent-discovery` background agent.

## What it does
1. **Read the intent's links.** Load the activating intent file's `chain` and
   `sources` frontmatter fields.
2. **QMD-first discovery.** Search the Plastic stores with
   `scripts/qmd-sync search "<terms>"` (or the `qmd` skill), scoped to the
   relevant `plastic-*` collections, across completed predecessor work named in
   `chain`/`sources` and any related parked/future intents in INDEX.md. Fall back
   to ripgrep over the stores only when QMD is absent.
3. **Deposit, never author.** Write findings to
   `resources/discovery--<slug>.md` in the intent directory ONLY. Do not write
   the intent file, spec.md, or any lifecycle deliverable. The lock-owner-only
   write rule stays intact; the Why-stage `plastic-brainstorming` agent reads the
   deposit and enriches `## Context`.

## Stage coverage
This is the What-stage agent in the one-agent-per-stage table (What:
intent-discovery, Why: brainstorming + spec-specialist, How: planner, Exec:
executor, Done: intent-curator).

## Boundaries
- Single output: `resources/discovery--<slug>.md`.
- Never takes the delivery lock (it runs before the lock is armed).
- Advisory input to Why, not a gate.
