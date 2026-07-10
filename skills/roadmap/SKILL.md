---
name: plastic-roadmap
description: Use when the user wants to plan a delivery batch, order waves of intents, ship a batch of tickets in one go, track a named collection of intents toward a goal, or asks for a "roadmap". Creates and maintains a roadmap file, a delivery-side collection of intents (the counterpart to a release), separate from INDEX.md status tracking.
user-invocable: true
---

# Roadmap

A roadmap is a named, ordered, delivery-side collection of intents: the delivery-side counterpart
to a release (completion-side, `CHANGELOG.md`). It lives at `roadmaps/{slug}.md`, a sibling of
`INDEX.md` wherever `INDEX.md` lives: the global tier's `~/.plastic/roadmaps/` (beside
`~/.plastic/INDEX.md`), or a project's root, `~/.plastic/projects/{slug}/roadmaps/` (beside that
project's `INDEX.md` and `project.yml`). It never sits inside `store/`, which holds intent
directories, not project artifacts.

A roadmap file has four parts: a title/meta header, `## Goal` (prose), `## Waves` (ordered; entries
inside a wave are parallel-safe, waves run sequentially), and an append-only dated `## Log`. Each
wave entry mirrors that intent's status in `INDEX.md` (`queued`/`delivering`/`delivered`/
`abandoned`/`blocked`).

**`INDEX.md` is the single writer of intent status; on any conflict INDEX wins and the roadmap
entry is corrected to match.**

The skill operates on the roadmap file directly via Read/Edit. The one deterministic helper it
uses is the savepoint ledger writer (`scripts/roadmap-savepoint`, `append`/`rebuild`); every verb's
closing step calls `append` after its Read/Edit, and the roadmap `.md` file itself stays
Read/Edit-only.

## Verbs

| Verb | When | Mechanics |
|------|------|-----------|
| Create | user wants to start a new roadmap / plan a delivery batch | `references/operations.md#create` |
| Add / reorder entries | user wants to add intents to a wave or resequence waves | `references/operations.md#add--reorder-entries` |
| Sync status mirror | an entry's status may be stale against INDEX | `references/operations.md#sync-status-mirror` |
| Append log line | a roadmap event just happened (created, wave done, closed) | `references/operations.md#append-a-log-line` |
| Read / consume | a human or a coordinator needs the roadmap's current state | `references/operations.md#read--consume` |
| Close / archive | the roadmap's `## Goal` is reached | `references/operations.md#close--archive` |

See `references/file-format.md` for the exact entry-line shape, status vocabulary, checkbox/log
format, and a worked example. See `references/operations.md` for step-by-step mechanics of each
verb above.

## Notes

- File location and the four-section shape are identical across tiers; do not invent a different
  layout per project. The general rule: `roadmaps/` is a sibling of `INDEX.md`, wherever `INDEX.md`
  lives.
- `## Goal` is a checkable prose condition read by a human or agent, not an executable checker.
- Wave entries render as checkboxes (`- [x] ... — delivered` / `- [ ] ... — <status>`); a human
  reading cold should see shipped/running/next within a minute. `## Log` lines are one-sentence,
  EM-to-CTO-voice, dated, and link each entry-intent's `outcome.md` (lossless-by-reference).
- Additive: this skill introduces no gate, lock, or hook, and does not change `INDEX.md`'s section
  list or the intent frontmatter schema.
- Closing a roadmap moves it to `roadmaps/archived/{slug}.md` so `roadmaps/` lists only live ones.
- Every verb also appends a machine ledger line to the roadmap's name-paired
  `roadmaps/{slug}.savepoint.md`, the derived counterpart to the human `## Log`; see
  `references/file-format.md` for its shape and location.
