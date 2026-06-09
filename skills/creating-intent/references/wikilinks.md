# Wikilink Conventions

| Syntax | Meaning |
|--------|---------|
| `[[ID]]` | Link to intent in same store (e.g., `[[1a1]]`) |
| `[[ID\|display text]]` | Link with human-readable label (e.g., `[[1a1\|Design Plastic]]`) |
| `[[global:ID]]` | Link to intent in `~/.plastic/store/` |
| `[[project-slug:ID]]` | Link to intent in `~/.plastic/projects/{slug}/store/` |

## Dual-Mode

This store works in two modes without modification:
- **Obsidian** (human, offline) — browse, link, write markdown
- **Programmatic** (any agent) — read/write via filesystem operations

No special tooling required for either mode.
