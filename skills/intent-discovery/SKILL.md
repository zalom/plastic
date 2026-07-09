---
name: plastic-intent-discovery
description: >-
  What-stage context deposit at intent activation: run QMD discovery over the
  intent's chain/sources and related parked intents, and write findings to
  resources/discovery--<slug>.md for the Why stage to consume. Use when an intent
  is activated (moved from Future to Active), after the lock is armed, under it,
  and before Why begins. Never writes the intent file itself.
---

# Intent Discovery — What-stage context deposit

Announce: "Discovering context for intent [ID] — [name]."

Runs once, at intent activation, after the lock is armed and before Why. It gathers what is
already known so Why does not start cold, and deposits it as a resource the
Why-stage brainstorming agent reads.

## When it fires
Inside `plastic-intent-starting`, right after the bridge is armed, under the
lock. Dispatched as the `plastic-intent-discovery` background agent.

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
   Shape the deposit tabular-first per `PLASTIC.md` (## Tabular-First Reporting, intent 160).

## Stage coverage
This is the What-stage agent in the one-agent-per-stage table (What:
intent-discovery, Why: brainstorming + spec-specialist, How: planner, Exec:
executor, Done: intent-curator).

## Boundaries
- Single output: `resources/discovery--<slug>.md`.
- Does not ACQUIRE the delivery lock itself; it runs under the lock the
  orchestrator armed, as the owner session (inherited session id), and is not
  blocked by it.
- Advisory input to Why, not a gate.
