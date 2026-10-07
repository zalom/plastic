# The grilling

The method `plastic intent spec` prints for the agent, before any node exists.

Ask the owner one question at a time. Keep asking until three things are
written: the goal, a done criterion for each piece of work, and the
decisions only the owner can make. Nothing else goes in a ruling. A fact the
agent can settle alone, a convention, a detail already in the code, none of
that is a ruling.

Record each owner decision with `plastic intent rule ID "TEXT"`. When a new
ruling replaces an older one, name it with `--supersedes RULING_ID`, and the
older ruling stays on record with the link that marks it superseded.
When the grilling changes the goal itself, rewrite it with `plastic intent
revise ID "LINE" --why "TEXT"`; the old What and Why stay as a revision.

The spec is done when `plastic intent spec` reads no open decision back. The
next step is `plastic auto start ID`.
