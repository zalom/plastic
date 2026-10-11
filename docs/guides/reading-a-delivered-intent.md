# Reading a delivered intent

Who this is for: someone who opened a finished intent and wants to know, fast,
what actually happened.

After this guide you will know exactly where to look, and in what order, to
find what shipped, whether it worked, and what to do next.

## Start from the truth, not the plan

An intent folder holds `intent.md`, `spec.md`, `graph.json`, `savepoint.md` and,
once it is finished, `outcome.md`. The spec and the graph describe what was
intended and how the work was split. Only `outcome.md` tells you what actually
shipped. Read it first, not `spec.md`.

Every finished intent has one, whether the work was delivered or abandoned:
`plastic intent end` and `plastic intent abandon` refuse to close an intent
without it.

## The reading order

1. **The status.** `plastic intent show ID` prints the intent's status, and
   `store/index.json` lists it for every intent of the store. A finished intent
   is `done`, with the disposition `delivered`, or `abandoned`, with the
   disposition `cancelled` or `superseded`.
2. **`outcome.md`.** Read what was delivered, then its `## Verification`
   section. A delivered intent carries a `Merged:` line and an
   `Architecture map:` line there, and often a `Pull request:` line. An
   abandoned intent carries a `Reverted:` line that says what was undone.
3. **`graph.json`.** Each node with its state and the findings it reported when
   it was done.
4. **`## Insights`** in `intent.md`. The rulings recorded while doing the work.
   This is where you find the reasoning behind decisions, and the intents that
   were opened as follow-ups.

You rarely need to read `spec.md` once an intent is done. It describes the
intention. `outcome.md` and the done nodes are what prove the intention became
reality.

## Why it works this way

`plastic intent end` closes an intent as delivered only once its verdict, its
nodes and its outcome allow it, and prints what is missing otherwise. The
status, the done nodes and the Verification lines of `outcome.md` agree by
construction. If they ever disagree, run `plastic sync up` and read the intent
again.

## What to read next

If you installed Plastic without QMD or Serena and want to know what that
changes, read
[working-without-qmd-and-serena.md](working-without-qmd-and-serena.md) next.
