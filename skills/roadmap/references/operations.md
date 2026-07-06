# Roadmap Operations

All six verbs operate on the Markdown file directly (Read/Edit). No helper script exists or is
needed; the file is small and the edits are mechanical.

**Human-comprehension goal.** Every operation below should leave the file such that a cold reader
(no INDEX.md, no intent directories open) can answer "what's shipped, what's running, what's
next" in under a minute, just from this one file.

## Create

1. Pick a `slug` (kebab-case, descriptive) and a `title`.
2. Resolve the store root (global `~/.plastic/store/` or the current project's
   `~/.plastic/projects/{slug}/store/`); create `roadmaps/` inside it if it does not exist yet.
3. Copy `templates/roadmap.md` to `roadmaps/{slug}.md`.
4. Fill the header (`# Roadmap: <title>` + the one-line meta) and write a real `## Goal` prose
   condition.
5. Add at least one `## Waves` wave with real entries (see Add / reorder below), each entry's
   status mirroring that intent's current `INDEX.md` status.
6. Append the first `## Log` line, a short dated plain-language note that the roadmap was created.

## Add / reorder entries

- **Add**: append an entry line (`- <intent-id> <title> — <status>`) to the target wave. Pick the
  intent's title and status straight from `INDEX.md`.
- **New wave**: add a new `### Wave N` heading after the last wave; entries in it are gated behind
  every earlier wave's entries leaving `queued`/`delivering`.
- **Reorder**: move an entry line to a different wave, or move a `### Wave` heading (with its
  entries) earlier or later. Reordering never changes an entry's status; it only changes when the
  entry is eligible to run.
- After any add/reorder, append a `## Log` line describing the change (e.g.
  `- <YYYY-MM-DD> added 132 to wave 2`).

## Sync status mirror

1. Read the intent's real status from `INDEX.md` (`## Active`, `## Future`, `## Completed`, or
   `## Abandoned`).
2. Compare to the roadmap entry's `<status>` token.
3. If they differ, **INDEX wins**: rewrite the roadmap entry's status token to match INDEX, and
   flip its checkbox in the same edit (`[x]` when the new status is `delivered`, `[ ]` otherwise).
   Never edit INDEX.md from the roadmap skill; the roadmap is a mirror, not a second writer.
4. Append a `## Log` line recording the change. When the new status is `delivered`, write the
   one-line EM-to-CTO entry described in `file-format.md` (date, what shipped and its impact in
   plain language, then a link to that intent's `outcome.md`). For other transitions, write a
   short dated plain-language line (no codenames, no jargon).

## Append a log line

- One line per event, dated `YYYY-MM-DD`, appended at the bottom of `## Log`. Never edit or delete
  an existing line (append-only).
- Every line is plain language a non-expert can read, never a codename or a raw `field -> value`.
  A delivery event follows the EM-to-CTO one-line shape with an `outcome.md` link (see
  `file-format.md`); bookkeeping events (created, an intent added to a wave, a wave completed, a
  roadmap closed) are short dated plain-language lines.

## Read / consume

- A human reading the file gets the current picture directly: `## Goal` for the target, `## Waves`
  for what is queued/delivering/delivered per wave (checkboxes give the shipped/not-shipped view at
  a glance), `## Log` for a one-line, plain-language history with a link into each intent's
  `outcome.md` for detail.
- A future coordinator (for example, an auto-mode dispatcher) reads `## Waves` top to bottom:
  a wave is eligible to dispatch once every entry in the previous wave is no longer
  `queued`/`delivering`; within an eligible wave, entries still `queued` are parallel-dispatchable.
  Always re-sync against `INDEX.md` before dispatch decisions, since INDEX is the source of truth.

## Close / archive

1. Confirm the roadmap's `## Goal` prose condition is met (every entry `delivered` or explicitly
   `abandoned` with a recorded reason, plus whatever else the goal states).
2. Create `roadmaps/archived/` in the store root if it does not exist yet.
3. Move the file: `roadmaps/{slug}.md` -> `roadmaps/archived/{slug}.md`. `roadmaps/` itself then
   lists only live (open or in-flight) roadmaps.
4. Append the final `## Log` line before or as part of the move: `- <YYYY-MM-DD> roadmap closed`.
