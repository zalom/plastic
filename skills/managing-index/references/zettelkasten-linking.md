# Zettelkasten Linking Reference

## Three Structural Layers

1. **Content notes** — individual intents (`~/.plastic/store/ID--slug/ID--slug.md`)
2. **Structure notes** — INDEX.md clusters that organize related intents
3. **Main structure note** — INDEX.md itself, the top-level entry point

## Three Connection Types (Ranked)

1. **Direct links** (strongest) — wikilinks in `## Links` section
2. **Sources/Chain** (knowledge graph) — `sources` array (backward), `chain` array (forward) in frontmatter
3. **Tags** (weakest) — shared tags, `project-<name>` for project membership

## When to Create a Cluster

A cluster is a structure note heading. Create one when:
- 3+ intents share a topic but aren't grouped
- You notice a pattern across intents
- A topic area is growing and needs an entry point

## Principles

- Links are the primary organizational mechanism, not folders
- Structure is a lens, not a container — intents remain first-class citizens
- Clusters are manually curated, not auto-generated
- Facts are invalidated, never deleted — completed intents stay in INDEX.md
