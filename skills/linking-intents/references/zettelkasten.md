# Zettelkasten Structure

Plastic implements three Zettelkasten structures:

| Structure | Implementation | Purpose |
|---|---|---|
| Folgezettel (linked list) | `sources` + `chain` in frontmatter | Sequential provenance |
| Directed graph (web of notes) | `## Links` with wikilinks | Obsidian navigation |
| Tag-based taxonomy | `tags` in frontmatter | Topic grouping |

INDEX.md is a structure note (hub), not a table of contents.

## Folgezettel IDs

IDs encode lineage using Luhmann's alternating convention:
- Root intents: sequential numbers (`1`, `2`, `3`...)
- Branches alternate letters and numbers: `1` → `1a` → `1a1` → `1a1a` → ...
- Multiple branches from the same parent increment: `1a`, `1b`, `1c`
- IDs are assigned at creation time and never change

## Knowledge Graph

`sources` + `chain` form the double-linked knowledge graph:
- `sources` = what fed into this intent (parents, inspirations, prerequisites)
- `chain` = what this intent produced (children, follow-ups, spin-offs)

## Dual-Mode

This store works in two modes without modification:
- **Obsidian** (human, offline) — browse, link, write markdown
- **Programmatic** (any agent) — read/write via filesystem operations

No special tooling required for either mode.
