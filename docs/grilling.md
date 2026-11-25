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

Write the spec in a file of your own, such as one in the intent's `resources/tmp/`, and pass it
with `plastic intent spec ID --from FILE`. The command writes `spec.md` and refuses a text that
lacks one of the four sections. Run it again with the whole new text each time the spec changes.

Record each owner decision with `plastic intent rule ID "TEXT"`. It takes the next
whole number and prints the decision the way a person writes it, such as `D3: TEXT`.
A decision that keeps the core of an earlier one and adds to it takes `--adds D3`,
which writes `D3.1`, then `D3.2`. A decision that changes the core takes
`--rewrites D3`: it replaces the text of `D3` and removes its additions, and the
work log keeps the old text. No number is used twice. In prose, name a set of
decisions the way a person does: "decisions `D1`, `D2` and `D4` to `D7` cover one thing".
When the grilling changes the goal itself, rewrite it with `plastic intent
revise ID "LINE" --why "TEXT"`; the old What and Why stay as a revision.

The spec is done when `plastic intent spec` reads no open decision back. The
next step is the go-ahead, `plastic intent approve ID`: the owner gives it in guided work, and
the agents record it in auto.
