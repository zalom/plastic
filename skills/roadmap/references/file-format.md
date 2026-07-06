# Roadmap File Format

## Location

`roadmaps/{slug}.md`, a store-root sibling of `INDEX.md`. Same layout in the global store
(`~/.plastic/store/roadmaps/{slug}.md`) and any project store
(`~/.plastic/projects/{slug}/store/roadmaps/{slug}.md`). Create the `roadmaps/` directory the
first time a store gets a roadmap.

`roadmaps/` lists only live (open or in-flight) roadmaps. Once a roadmap's `## Goal` is reached,
its file moves to `roadmaps/archived/{slug}.md` (see Close/archive in `operations.md`); the
`archived/` subdirectory is scaffolded once, alongside `roadmaps/`, with a `.gitkeep`.

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

One line per intent, inside its wave, as a Markdown checkbox:

```
- [x] <intent-id> <title> — delivered
- [ ] <intent-id> <title> — <status>
```

`<intent-id>` and `<title>` match the intent's `INDEX.md` entry (terse, not a summary). The
checkbox is checked (`[x]`) once `<status>` is `delivered`, unchecked (`[ ]`) for every other
status. The checkbox is a rendering of the mirrored status token, not a second piece of state: a
human scanning the file sees at a glance what shipped (checked) and what has not (unchecked),
while the trailing token still carries the precise state (`queued`/`delivering`/`blocked`/
`abandoned`) when unchecked.

## Status vocabulary

`queued` | `delivering` | `delivered` | `abandoned` | `blocked`

Status is a **mirror** of `INDEX.md`. `INDEX.md` is the single writer of intent status; on any
conflict INDEX wins and the roadmap entry (both its token and its checkbox) is corrected to match
it. The roadmap never sets a status that INDEX does not already reflect.

## Log line shape

One line per event, dated, in plain-language EM-to-CTO voice: what shipped and why it matters to a
non-expert reader, no jargon or internal codenames, ending with a link to that entry-intent's
`outcome.md`:

```
- <YYYY-MM-DD> <one plain-language sentence: what shipped, its impact> — see store/<id>--<slug>/outcome.md
```

The log line never restates `outcome.md` detail; it points at it (lossless-by-reference). This
complements, and does not replace, `INDEX.md`'s `## Completed` section or `CHANGELOG.md`.

## Worked example

```
# Roadmap: Stable 1.0

Delivery-side collection of intents that close out the pre-1.0 hardening pass, plastic project store.

## Goal
All intents below are delivered, the suite is green, and a 1.0.0 release is cut.

## Waves
Entries in a wave are parallel-safe; waves run top to bottom. The checkbox tracks delivered/not;
the token after the em-dash carries the precise mirrored status (queued | delivering | delivered |
abandoned | blocked); INDEX wins on any conflict.

### Wave 1
- [x] 121 Fix bash gate redirect parsing — delivered
- [ ] 130 Proportional cycle tiers — delivering

### Wave 2
- [x] 124 Roadmap feature — delivered

## Log
- 2026-07-06 Shipped the bash-gate redirect fix so quoted arrows and heredoc trailers stop
  blocking legitimate commits — see store/121--fix-bash-gate-redirect-parsing/outcome.md.
```
