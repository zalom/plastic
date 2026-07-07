# Reading a delivered intent

Who this is for: someone who opened a finished intent and wants to know, fast,
what actually happened.

After this guide you will know exactly where to look, and in what order, to
find what shipped, whether it worked, and what to do next.

## Start from the truth, not the plan

An intent carries several files: `spec.md`, `plan.md`, `checklist.md`, and, once
it is finished, `outcome.md`. The first two describe what was intended before
the work started. Only `outcome.md` tells you what actually shipped. Read it
first, not `spec.md`.

Every finished intent has one, whether the work was delivered or abandoned.
`outcome.md` starts with a header that says which:

```
disposition: delivered|abandoned
```

If the work landed, `disposition: delivered`. If it was called off partway
through, `disposition: abandoned`, and the file explains why.

## The reading order

1. **The index status line.** Every project keeps an `INDEX.md` file listing
   its intents. Find the one-line entry for your intent. It is the canonical
   record of whether the intent is Active, Completed, or Abandoned. If
   anything else disagrees with this line, the index wins.
2. **`outcome.md`.** Read its four sections: Summary (what was delivered, in
   a sentence or two), Delivered (the concrete list of changes), Verification
   (each acceptance criterion and how it was checked), and Follow-ups (what
   comes next, if anything).
3. **The intent file's own `## Outcome` section.** A short, one or two line
   recap living in the intent file itself, for a quick glance without opening
   `outcome.md`.
4. **`## Insights`.** The running log of things learned while doing the work.
   This is where you find the reasoning behind decisions, and any new intents
   that were spawned as follow-ups.

You rarely need to read `spec.md` or `plan.md` once an intent is done. They
describe the intention. `outcome.md` and the checked-off checklist are what
prove the intention became reality.

## Why it works this way

Plastic will not let an intent finish, delivered or abandoned, without a
matching `outcome.md`. This keeps the three signals of "done" in agreement:
the index status, the outcome file, and a short automatic log entry. If any of
these disagree, something is wrong, and the index status is the one to trust.

## What to read next

If you installed Plastic without QMD or Serena and want to know what that
changes, read
[working-without-qmd-and-serena.md](working-without-qmd-and-serena.md) next.
