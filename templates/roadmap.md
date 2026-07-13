# Roadmap: <name>

(one-line meta: what this roadmap delivers, and which tier it lives in. `roadmaps/` is a sibling
of `INDEX.md` — a project's root or the global `~/.plastic/`, never inside `store/`. When this
roadmap's goal is reached, move this file from `roadmaps/{slug}.md` to
`roadmaps/archived/{slug}.md`; `roadmaps/` itself lists only live roadmaps.)

## Goal
(a checkable prose condition — one or a few sentences a human or coordinator reads to decide the
roadmap is done. Not an executable checker.)

## Batches
Entries in a batch are parallel-safe; batches run top to bottom. The checkbox is checked once an
entry is delivered, unchecked otherwise; the trailing token after the em-dash is the precise
mirrored status (queued | delivering | delivered | abandoned | blocked) from INDEX.md. INDEX
always wins on any conflict between the checkbox/token here and INDEX's real status.

### Batch 1
- [ ] <intent-id> <title> — queued
- [ ] <intent-id> <title> — queued

### Batch 2
- [x] <intent-id> <title> — delivered

## Log
(append-only, dated, one line per event. Each line is one plain-language, EM-to-CTO-voice sentence:
what shipped and its impact for a non-expert reader, no jargon or internal codenames, ending with a
link to that entry-intent's `outcome.md`. Never restate outcome detail here; link to it instead.
Newest at the bottom.)
- 2026-01-01 00:00 UTC Shipped the first batch of this roadmap; see store/<intent-id>--<slug>/outcome.md.
