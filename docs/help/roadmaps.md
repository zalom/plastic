# Roadmaps

This chapter holds the roadmap file format and how a roadmap runs.

Roadmaps exist for planned parallel delivery of intents in a coherent and organized way. A roadmap
is a named, ordered, delivery-side collection of intents: the delivery-side counterpart to a
release (completion-side, tracked in `CHANGELOG.md`). Create one by hand from the template, then
use `plastic roadmap show`, `next`, `log`, `check`, and `migrate` to read, drive, audit, and
upgrade it.

File location: `roadmaps/{slug}.md`, a sibling of `INDEX.md`, wherever `INDEX.md` lives, never
inside `store/` (store holds intent directories, not project artifacts). For a project that is its
root, `~/.plastic/stores/{slug}/roadmaps/`, beside `project.yml`; for the global store it is
`~/.plastic/stores/global/roadmaps/`, beside its `INDEX.md`. Legacy homes keep their
previous paths until an update moves them. `roadmaps/` lists only live (open or
in-flight) roadmaps: once a roadmap's goal is reached, move it by hand to
`roadmaps/archived/{slug}.md`. Its ledger and its screens still resolve it there.

A roadmap file from the template has five sections, in order: a title/meta header, `## Goal`,
`## Graph`, `## Batches`, and an append-only dated `## Log`.
`## Goal` is a checkable prose condition read by a human or agent, not an executable checker.
`## Graph` holds the `needs` edges between entries, and the batches are computed from them;
A roadmap that has no Graph section is rebuilt from its batch order. `## Batches` holds ordered batches; entries inside a batch are parallel-safe,
batches run sequentially, top to bottom. A roadmap may use the heading `## Waves` in place of
`## Batches`; the tooling reads both and never renames a roadmap file to change it.

Each batch entry carries a status token (`queued`/`delivering`/`delivered`/`abandoned`/`blocked`)
that mirrors that intent's status in `INDEX.md`. `INDEX.md` is the single writer of intent status;
on any conflict INDEX wins and the roadmap entry is corrected to match.

**Human-comprehension surface.** A roadmap is also written to be read cold. Batch entries render as
checkboxes (checked once delivered, unchecked otherwise) next to the status token, and each `## Log`
line is one plain-language sentence, starting `YYYY-MM-DD HH:MM UTC`, written the way an
engineering manager would brief a non-expert executive: what shipped and why it matters, no jargon
or codenames, ending with a link
to that intent's `outcome.md`. The log points at the detail instead of repeating it, so a person
opening the file with no other context can tell what shipped, what is running now, and what is
next in under a minute.

**Running a roadmap.** A roadmap is the planning half of the work. Batches lay out the
parallelism plan: what can run together, and in what order. `plastic auto` delivers a roadmap
in auto mode.
