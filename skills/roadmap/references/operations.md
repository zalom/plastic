# Roadmap Operations

All five verbs operate on the Markdown file directly (Read/Edit). No helper script exists or is
needed; the file is small and the edits are mechanical.

## Create

1. Pick a `slug` (kebab-case, descriptive) and a `title`.
2. Resolve the store root (global `~/.plastic/store/` or the current project's
   `~/.plastic/projects/{slug}/store/`); create `roadmaps/` inside it if it does not exist yet.
3. Copy `templates/roadmap.md` to `roadmaps/{slug}.md`.
4. Fill the header (`# Roadmap: <title>` + the one-line meta) and write a real `## Goal` prose
   condition.
5. Add at least one `## Waves` wave with real entries (see Add / reorder below), each entry's
   status mirroring that intent's current `INDEX.md` status.
6. Append the first `## Log` line: `- <YYYY-MM-DD> created`.

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
3. If they differ, **INDEX wins**: rewrite the roadmap entry's status token to match INDEX. Never
   edit INDEX.md from the roadmap skill; the roadmap is a mirror, not a second writer.
4. Append a `## Log` line recording the change: `- <YYYY-MM-DD> <id> status -> <new-status>`.

## Append a log line

- One line per event, dated `YYYY-MM-DD`, appended at the bottom of `## Log`. Never edit or delete
  an existing line (append-only).
- Typical events: `created`, `<id> added to wave N`, `wave N completed`, `<id> status -> <status>`,
  `roadmap closed`.

## Read / consume

- A human reading the file gets the current picture directly: `## Goal` for the target, `## Waves`
  for what is queued/delivering/delivered per wave, `## Log` for history.
- A future coordinator (for example, an auto-mode dispatcher) reads `## Waves` top to bottom:
  a wave is eligible to dispatch once every entry in the previous wave is no longer
  `queued`/`delivering`; within an eligible wave, entries still `queued` are parallel-dispatchable.
  Always re-sync against `INDEX.md` before dispatch decisions, since INDEX is the source of truth.
