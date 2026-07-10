# Zettelkasten Structure

Plastic implements three Zettelkasten structures:

| Structure | Implementation | Purpose |
|---|---|---|
| Folgezettel (linked list) | `sources` + `chain` in frontmatter | Sequential provenance |
| Directed graph (web of notes) | `## Links` with wikilinks | Obsidian navigation |
| Tag-based taxonomy | `tags` in frontmatter | Topic grouping |

INDEX.md is a structure note (hub), not a table of contents.

`## Links` mirrors the frontmatter graph exactly. Each entry is
`- [[id--slug|<target's full intent: text>]]` (cross-store: `- [[store:id--slug|...]]`),
a clickable `id--slug` target with the target's full `intent:` text as the label.
Ordering is mandatory: all `sources` first (top), then all `chain`, frontmatter order
preserved within each group. Sources never appear at the end. No source/chain tags, no
sub-grouping. An intent with empty `sources` and `chain` carries the empty-state comment.

## Folgezettel IDs

IDs encode lineage using Luhmann's alternating convention:
- Root intents: sequential numbers (`1`, `2`, `3`...)
- Branches alternate letters and numbers: `1` → `1a` → `1a1` → `1a1a` → ...
- Multiple branches from the same parent increment: `1a`, `1b`, `1c`
- IDs are assigned at creation time and never change

## Knowledge Graph

`sources` and `chain` form the directed knowledge graph:
- `sources` = the direct ascendant(s) this intent was created from / emerged from the
  lifecycle of (formation, not topic similarity); a DAG (acyclic), strong must-load context.
- `chain` = forward continuations AND related-but-not-spawned successors it leads to; a
  directed graph that may cycle, lighter contributory context.
- Reciprocity is one-directional: every `sources` edge has a reciprocal `chain` entry (I1),
  but `chain` may carry relational entries with no reciprocal `sources` (I2), so the graph is
  NOT strictly double-linked.

## Dual-Mode

This store works in two modes without modification:
- **Obsidian** (human, offline) — browse, link, write markdown
- **Programmatic** (any agent) — read/write via filesystem operations

No special tooling required for either mode.
