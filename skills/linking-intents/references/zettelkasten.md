# Zettelkasten Structure

Plastic implements three Zettelkasten structures:

| Structure | Implementation | Purpose |
|---|---|---|
| Folgezettel (linked list) | `sources` + `chain` in frontmatter | Sequential provenance — what led here, what spawned from here |
| Directed graph (web of notes) | `## Links` with wikilinks | Obsidian graph navigation, human-facing connections |
| Tag-based taxonomy | `tags` in frontmatter | Grouping by topic and project membership |

INDEX.md is a structure note (hub), not a table of contents. It clusters intents
by meaning. Project hubs in INDEX.md represent deliverable groupings.

## Folgezettel ID Format

IDs encode lineage using Luhmann's alternating convention:
- Root intents: sequential numbers (`1`, `2`, `3`...)
- Branches alternate letters and numbers: `1` → `1a` → `1a1` → `1a1a` → ...
- Multiple branches from the same parent increment: `1a`, `1b`, `1c` or `1a1`, `1a2`, `1a3`
- IDs are assigned at creation time and never change

## Directory Naming

Format: `ID--three-to-five-words` — applies to all stores.
- `ID` — Folgezettel identifier
- `--` — separator
- `three-to-five-words` — human-readable slug (3-5 words max)

## Intent Filename

The intent file is named `{ID}--{slug}.md` — matching the directory name.
Wikilinks use the ID only (`[[1a1]]`) and resolve via Obsidian alias or search.

Examples:
- Directory `1a1--design-plastic-state-system/` contains `1a1--design-plastic-state-system.md`
- Directory `4a1b--lifecycle-file-mapping/` contains `4a1b--lifecycle-file-mapping.md`

## Wikilink Conventions

| Syntax | Meaning |
|--------|---------|
| `[[ID]]` | Link to intent in same store |
| `[[ID\|display text]]` | Link with human-readable label |
| `[[global:ID]]` | Link to intent in `~/.plastic/store/` |
| `[[project-slug:ID]]` | Link to intent in `~/.plastic/projects/{slug}/store/` |
