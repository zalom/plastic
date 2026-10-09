---
disposition: delivered|abandoned
---
# Outcome: <intent name>

## Summary
(what was delivered)

## Delivered
<!-- One row per thing delivered, in plain wording a reader recognizes, not
an implementation summary; the technical detail belongs in ## Summary. Each
row's label must appear as a standalone token in an actions/*.md OR
nodes/*.md heading that owns the matrix table (for example "### S1 - ..."
with a table beneath it proves row S1, or "## n1 failure-mode matrix" proves
row n1); that heading's matrix rows become the row's Proven-by cell on the
delivered screen. Readers resolve actions/ first, then nodes/. A label with no
owning heading falls back to a matrix row cell that carries it, when one under
a heading named "matrix" exists. -->
| Row | What |
| --- | --- |
| S1 | ... |

## Verification
- <acceptance criterion>: verified by ... → result

## Needs you
<!-- The literal None, or a table shaped | N | What | Why | with one row per
open owner action. Prose is tolerated by the reader but renders as a single
untyped row - write the table. -->
None

## Follow-ups
None
