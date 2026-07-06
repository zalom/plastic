# Roadmap File Format

## Location

`roadmaps/{slug}.md`, a store-root sibling of `INDEX.md`. Same layout in the global store
(`~/.plastic/store/roadmaps/{slug}.md`) and any project store
(`~/.plastic/projects/{slug}/store/roadmaps/{slug}.md`). Create the `roadmaps/` directory the
first time a store gets a roadmap.

## The four sections (in order)

1. **Title/meta header** — `# Roadmap: <name>` plus a one-line meta sentence naming what the
   roadmap delivers and which store it lives in.
2. **`## Goal`** — a checkable prose condition: one or a few sentences a human or coordinator reads
   to decide the roadmap is done. Not an executable checker, not a list of tasks.
3. **`## Waves`** — ordered waves (`### Wave 1`, `### Wave 2`, ...). Entries inside a wave are
   parallel-safe (can be dispatched together); waves run top to bottom, sequentially (wave 2 does
   not start until wave 1's entries are no longer `queued`/`delivering`).
4. **`## Log`** — append-only, dated, one line per event. Newest entry at the bottom. Never edit or
   remove an existing log line.

## Entry line shape

One line per intent, inside its wave:

```
- <intent-id> <title> — <status>
```

`<intent-id>` and `<title>` match the intent's `INDEX.md` entry (terse, not a summary).
`<status>` is one of the five tokens below.

## Status vocabulary

`queued` | `delivering` | `delivered` | `abandoned` | `blocked`

Status is a **mirror** of `INDEX.md`. `INDEX.md` is the single writer of intent status; on any
conflict INDEX wins and the roadmap entry is corrected to match it. The roadmap never sets a
status that INDEX does not already reflect.

## Worked example

```
# Roadmap: Stable 1.0

Delivery-side collection of intents that close out the pre-1.0 hardening pass, plastic project store.

## Goal
All intents below are delivered, the suite is green, and a 1.0.0 release is cut.

## Waves
Entries in a wave are parallel-safe; waves run top to bottom. Each entry mirrors INDEX status
(queued | delivering | delivered | abandoned | blocked); INDEX wins on any conflict.

### Wave 1
- 121 Fix bash gate redirect parsing — delivering
- 130 Proportional cycle tiers — delivering

### Wave 2
- 124 Roadmap feature — delivering

## Log
- 2026-07-06 created
```
