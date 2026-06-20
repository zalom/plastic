# How Plastic sources and chains intents

This is the operating model behind the `sources` and `chain` frontmatter fields. It
explains how Plastic borrows from Zettelkasten, what each field means, the invariants that
keep the graph honest, and the context contract (the operational reason the two fields are
weighted differently). Every other surface (PLASTIC.md, the skills, the scripts) restates a
slice of this model; this document is the source of truth.

## Grounding: from a paper tree to a software graph

In a Zettelkasten, the Folgezettel ID is a strict single-parent TREE. The ID is a physical
address ("where the note lives on paper"): `1` leads to `1a`, `1a` leads to `1a1`, and a
sibling branch increments to `1b`. A note has exactly one structural parent, so the ID tree
is acyclic and records where a thought has been, not everything it relates to.

A paper tree cannot express the cross-branch relations a real body of thought has: a note on
branch `3c` can be formed from a note on branch `1a`, and it can lead to a note on branch
`7`. Plastic promotes the paper tree into a queryable directed graph by adding two
frontmatter fields, `sources` and `chain`. Both coexist with the ID: Plastic is a valid
Zettelkasten on paper (the ID tree) AND a graph in code (the `sources` / `chain` edges).

## The five structures (Zettelkasten to Plastic)

| Structure | What it is | Shape | Role |
|---|---|---|---|
| ID | single-parent tree (Folgezettel address) | acyclic tree | human/paper lineage, "where it has been" |
| `sources` | formative in-edges | DAG (multi-parent, cross-branch), acyclic | "how it was formed", strong creational/foundational context (must-load) |
| `chain` | forward out-edges | general directed graph, cycles allowed | "what it leads to / could contribute", lighter contributory context |
| `## Links` | human-readable projection of the local graph | rendered section | all `sources` first (top, named), then all `chain` (named), as `[[id]]` wikilinks plus a short label |
| tags + INDEX.md | register / entry points | inverted index, hubs | how you find a cluster without walking edges |

The ID and `sources` are both about lineage, but they answer different questions. The ID is
the single paper parent (one structural address). `sources` is the full set of formative
ascendants (possibly several, possibly cross-branch), so a branch's structural parent is
ALSO written to `sources` (see the redundant-explicit rule below).

## The two definitions

These two definitions replace all "influenced", "inspired", or "fed into" language. Topic
similarity is not a `sources` edge.

- D1: `sources` = the direct ascendant(s) the intent was CREATED FROM, the intent(s) it
  emerged from the lifecycle of. Formation, not topic similarity.
- D2: `chain` = forward continuations AND related-but-not-spawned successors it leads to.

## The five invariants

- I1 (formative reciprocity, auto-fixable): if `A` is in `B.sources`, then `B` must be in
  `A.chain`.
- I2 (no false symmetry): if `A` is in `B.chain`, that does NOT require `B` in `A.sources`.
  A relational-only `chain` entry is valid and must never be "corrected away."
- I3 (per-node disjoint): for any node `X`, `X.sources` and `X.chain` share no id.
- I4 (no danglers): every id in any `sources` or `chain` resolves to a real intent.
- I5 (`## Links` projection): `## Links` is the human-readable projection of the local
  graph, all `sources` first (top, named), then all `chain` (named), as `[[id]]` wikilinks
  plus a short label.

## Construction rules

- Branch-vs-root by ORIGIN, not topic. You branch when the new work cannot stand without its
  parent; you root when it can. This is enforced by D1.
- Redundant-explicit: a branch's structural parent is ALSO written to `sources`. The ID
  carries the parent for the human/paper tree; `sources` carries it for software.
- All `sources` surface in `## Links`, listed first (top, named), above the `chain`
  relations.
- Related-but-not-spawned: a new intent merely related to (or inspired by) another, but not
  created from it, carries NO `sources`. Record the relation on the PREDECESSOR's `chain`,
  and mirror it as a `[[id]]` wikilink in `## Links`.
- Cycles: `sources` is acyclic (a creational DAG); `chain` may cycle (mutual contribution is
  natural).
- Governing-intent exception: KEEP `sources` for a project's governing intent. A project
  genuinely IS formed from its founding intent (a true formative edge), reciprocated on the
  founding intent's `chain`.

## The context contract (the operational why)

`sources` and `chain` are not just provenance bookkeeping. They are the context an agent (and
a human) loads to deliver an intent, and the two fields carry different weight. Knowing WHY
they differ, not only how to fill them, is the point of the contract.

- `sources` = strong, creational/foundational context, the "thoughts that created other
  thoughts." Must-load: when you deliver an intent you load its `sources` first, because they
  are what it was built from. Formation is causal, so the `sources` graph is acyclic (a DAG):
  nothing is foundationally created from something downstream of it.
- `chain` = lighter, contributory context, "a thought that could contribute; a good idea for
  adding more to the original." It is the network for discovering how intents affect each
  other, a neural-pathways graph, so cycles are allowed (mutual contribution is natural).
  Traverse it lightly and optionally for discovery, not as a mandatory load.

This contract is what the runtime context loader consumes (sibling intents [[13b]] and
[[66a]] own the loader). This document only STATES the contract; it does not build the
consumer.

## Worked example: related-but-not-spawned

Intent 68 (this very document's intent) is the live example. It was not created out of the
lifecycle of intent 60; it is related work that intent 60 leads to. So:

- Intent 68 carries NO `sources` pointing at 60 (it was not created from 60).
- Intent 60's `chain` lists 68 (the relation lives on the predecessor's forward edge).
- A `[[68]]` wikilink mirrors the relation in intent 60's `## Links`.

Contrast the created-from case: a branch `14a` or a root genuinely created from intent 14
DOES carry `14` in its `sources`, and intent 14's `chain` gains the new id (I1). The
difference is origin, not topic: created-from goes in `sources`; merely-related goes only on
the predecessor's `chain`.
