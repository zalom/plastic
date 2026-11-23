# The grilling

The method `plastic intent spec` prints for the agent, before any node exists.

Ask the owner one question at a time. Keep asking until these are written in
`spec.md`: the goal, a done criterion for each piece of work, the decisions
only the owner can make, and the constraints. Nothing else goes in a ruling. A fact the
agent can settle alone, a convention, a detail already in the code, none of
that is a ruling.

The sections of `spec.md` are `## Goal`, `## Done criteria`, `## Open decisions` and
`## Constraints`. Each done criterion is a bullet that starts with its key, such as
`- [c1] text`. Under `## Constraints`, a bullet says what the work must keep true. The
claim packet of a node carries those bullets, the first 20 of them.

Record each owner decision with `plastic intent rule ID "TEXT"`. When a new
ruling replaces an older one, name it with `--supersedes RULING_ID`, and the
older ruling stays on record with the link that marks it superseded.
When the grilling changes the goal itself, rewrite it with `plastic intent
revise ID "LINE" --why "TEXT"`; the old What and Why stay as a revision.

The spec is done when `plastic intent spec` reads no open decision back. The
next step is the go-ahead, `plastic intent approve ID`: the owner gives it in guided work, and
the agents record it in auto.
