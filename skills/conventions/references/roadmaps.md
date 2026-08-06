# Roadmaps

This chapter holds the full roadmap file format and its relationship to INDEX.md status and to loop engineering.

### Roadmaps

Roadmaps exist for planned parallel delivery of intents in a coherent and organized way. A roadmap
is a named, ordered, delivery-side collection of intents: the delivery-side counterpart to a
release (completion-side, tracked in `CHANGELOG.md`). Use `plastic-roadmap` to create, order,
close, and consume one.

File location: `roadmaps/{slug}.md`, a sibling of `INDEX.md`, wherever `INDEX.md` lives, never
inside `store/` (store holds intent directories, not project artifacts). For a project that is its
root, `~/.plastic/projects/{slug}/roadmaps/`, beside `project.yml`; for the global tier it is
`~/.plastic/roadmaps/`, beside `~/.plastic/INDEX.md`. `roadmaps/` lists only live (open or
in-flight) roadmaps: once a roadmap's goal is reached, it moves to `roadmaps/archived/{slug}.md`,
a sibling subdirectory scaffolded once with a `.gitkeep`.

A roadmap file has four sections, in order: a title/meta header, `## Goal`, `## Batches`, and an
append-only dated `## Log`. `## Goal` is a checkable prose condition read by a human or agent, not
an executable checker. `## Batches` holds ordered batches; entries inside a batch are
parallel-safe, batches run sequentially, top to bottom. A roadmap written before owner ruling 145
may instead use the legacy `## Waves` heading; the tooling accepts both, but never renames an
existing roadmap file to migrate it.

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

**Relationship to loop engineering (intent 69).** A roadmap is the planning half of the work; the
loop is its runtime. Batches lay out the parallelism plan: what can run together, and in what order.
Loop engineering (intent 69, not yet delivered) is expected to consume that plan and supply the
running parts, the heartbeat, how many dispatches run at once, checking the goal, and resuming
after a stop. This section only states the relationship and points to intent 69 as the future
consumer; it does not change intent 69's own design.
