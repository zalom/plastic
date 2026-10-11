# Roadmaps

This chapter holds what a roadmap holds and how a roadmap runs.

Roadmaps exist for planned parallel delivery of intents in a coherent and organized way. A roadmap
is a named, ordered, delivery-side collection of intents: the delivery-side counterpart to a
release (completion-side, tracked in `CHANGELOG.md`).

| Step | Command |
| --- | --- |
| create the roadmap | `plastic roadmap new NAME --title TITLE --goal GOAL` |
| write one batch | `plastic roadmap batch SLUG N --title TITLE --done TEXT` |
| add an item to a batch | `plastic roadmap add SLUG N ITEM --needs ITEM` |
| open a ready item's intent | `plastic roadmap open SLUG ITEM` |
| read it | `plastic roadmap show SLUG`, `plastic roadmap next SLUG` |
| audit it | `plastic roadmap check SLUG` |
| log what happened | `plastic roadmap log SLUG TEXT` |
| deliver it in auto mode | `plastic auto SLUG` |

A roadmap is a set of rows in the store's databases. The rows print to `roadmaps/{slug}.md` in
the store folder, `~/.plastic/stores/{slug}/roadmaps/`, with these sections in order: the title,
`## Goal`, one `## Batch N: TITLE` section for each batch, `## Graph` and `## Log`.
`## Goal` is a checkable prose condition read by a human or agent, not an executable checker.
`## Graph` holds the `needs` edges between items. Items inside a batch are parallel-safe, and
batches run sequentially, top to bottom.

Each item's state is derived, never stored: `done` once its intent is done or abandoned,
`dropped` after `plastic roadmap drop`, `in flight` while its intent is open, active or parked,
`blocked` while an item it needs is unresolved, and `ready` otherwise. A done or dropped item
renders with a checked checkbox.

**Human-comprehension surface.** A roadmap is also written to be read cold. Each `## Log` line
carries its UTC time and one plain-language sentence, written the way an engineering manager
would brief a non-expert executive: what shipped and why it matters, no jargon or codenames,
ending with a link to that intent's `outcome.md`. The log points at the detail instead of
repeating it, so a person opening the file with no other context can tell what shipped, what is
running now, and what is next in under a minute.

**Running a roadmap.** A roadmap is the planning half of the work. Batches lay out the
parallelism plan: what can run together, and in what order. `plastic auto` delivers a roadmap
in auto mode.
