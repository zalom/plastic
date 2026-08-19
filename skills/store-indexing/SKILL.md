---
name: plastic-store-indexing
description: Use after creating, completing, or abandoning intents, when the user says "index" or "organize", or when INDEX.md needs maintenance. Curates the INDEX.md structure note.
user-invocable: false
---

# Managing the Index

## When to Use
- After creating a new intent (automatic - part of intent-creating workflow)
- After completing or abandoning an intent
- User says "index", "organize", or "clean up"
- Periodic maintenance when the store grows

## INDEX.md Structure

INDEX.md is a Zettelkasten main structure note - the brain's entry point. It has five sections:

### Active
Intents currently being worked on. Max 1-2 for focus.
```markdown
## Active
- [1a2 — Design Plastic](store/1a2--design-plastic-state-system/1a2--design-plastic-state-system.md) — decision, human
```

### Future
Intents parked for later. May be picked up by agents.
```markdown
## Future
- [1b1 — Build Reddit KB](store/1b1--build-reddit-knowledge-base/1b1--build-reddit-knowledge-base.md) — implementation, human
```

### Clusters
Topic-based groupings. Manually curated. Create a new cluster when 3+ intents share a topic.
```markdown
## Clusters
### Reddit Knowledge Base
- [1a — Research](store/1a--research-reddit-saved-posts/1a--research-reddit-saved-posts.md)
- [1a1 — Plan](store/1a1--plan-reddit-knowledge-base/1a1--plan-reddit-knowledge-base.md)
```

### Abandoned
Intents ended without delivery. Links preserved, never deleted.

### Completed
All completed intents with dates. Links preserved, never deleted.

When you move an intent INTO Completed or Abandoned, do these things:

1. Author a real `outcome.md` in the intent directory from `~/.plastic/templates/outcome.md`, with the frontmatter `disposition: delivered` for a completed intent or `disposition: abandoned` for an abandoned one. `outcome.md` is MANDATORY at every terminal, delivered and abandoned alike: on abandon it records the abandonment reason and replaces the scaffolded placeholder sentinel (never leave `outcome.md` a placeholder at a terminal).
2. Call `plastic-intent-ending` for the terminal-transition close (INDEX move, savepoint `Done` bookend, store commit, disarm, and the QMD reindex last): `ruby ~/.plastic/scripts/end-intent --store <store> --id <id> --disposition delivered|abandoned`, then follow that skill's own disarm and reindex steps. Never restate those one-liners here.

## Workflow

QMD-first (when available): when you need to locate a specific intent (to reclassify, flag, or
cluster it) rather than rebuild every section, before scanning the store with grep/Read run
`ruby ~/.plastic/scripts/qmd-sync search "<terms>"` to surface candidate or related intents, then
open the authoritative intent file for any hit you act on. The command is a no-op when QMD is
absent, so fall back to the directory scan below.

### Rebuild Sections
Scan the active store's `store/` directory for intent files and rebuild each section:

```bash
for dir in $STORE_ROOT/store/*/; do
  f=$(find "$dir" -maxdepth 1 -name "*.md" ! -name "spec.md" ! -name "plan.md" ! -name "checklist.md" ! -name "outcome.md" ! -name "savepoint.md" | head -1)
  [ -n "$f" ] && dirname_slug=$(basename "$dir") && ruby -e '
    data = File.read(ARGV[0]).split("---")[1]
    parsed = YAML.safe_load(data)
    puts "#{parsed["id"]}|#{parsed["intent"]}|#{ARGV[1]}"
  ' "$f" "$dirname_slug" 2>/dev/null
done | sort -t'|' -k1
```

### Suggest Clusters
When 3+ intents share tags but aren't in a cluster, suggest a new cluster heading.

### Flag Orphans
Intents with no links (empty `sources`, empty `chain`, no `## Links` entries, not in any cluster) should be flagged for curation.

Before reclassifying a structural finding outside routine indexing, read
`../plastic-conventions/references/maintenance-and-revisions.md` for WORK versus MAINTENANCE, the
`revisions.md` move-and-record contract, and the violation-tag catalog.

REQUIRED BACKGROUND: intent-linking (for understanding connection types and Zettelkasten theory)

Read `../plastic-conventions/references/knowledge-graph.md` for the linking doctrine: tiers of
influence, sources versus chain, and the `## Links` projection. This path resolves relative to
this skill's own installed directory.

## References

- Read `references/zettelkasten-linking.md` for the three structural layers (Folgezettel, directed graph, tags) and how they map to INDEX.md organization
