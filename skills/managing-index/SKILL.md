---
name: plastic-managing-index
description: Use after creating, completing, or abandoning intents, when the user says "index" or "organize", or when INDEX.md needs maintenance. Curates the INDEX.md structure note.
---

# Managing the Index

## When to Use
- After creating a new intent (automatic — part of creating-intent workflow)
- After completing or abandoning an intent
- User says "index", "organize", or "clean up"
- Periodic maintenance when the store grows

## INDEX.md Structure

INDEX.md is a Zettelkasten main structure note — the brain's entry point. It has four sections:

### Active
Intents currently being worked on. Max 1-2 for focus.
```markdown
## Active
- [1a2 — Design Plastic](store/1a2--design-plastic-state-system/1a2.md) — decision, human
```

### Future
Intents parked for later. May be picked up by agents.
```markdown
## Future
- [1b1 — Build Reddit KB](store/1b1--build-reddit-knowledge-base/1b1.md) — implementation, human
```

### Clusters
Topic-based groupings. Manually curated. Create a new cluster when 3+ intents share a topic.
```markdown
## Clusters
### Reddit Knowledge Base
- [1a — Research](store/1a--research-reddit-saved-posts/1a.md)
- [1a1 — Plan](store/1a1--plan-reddit-knowledge-base/1a1.md)
```

### Completed
All completed intents with dates. Links preserved, never deleted.

## Workflow

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

REQUIRED BACKGROUND: linking-intents (for understanding connection types and Zettelkasten theory)

## References

- Read `references/zettelkasten-linking.md` for the three structural layers (Folgezettel, directed graph, tags) and how they map to INDEX.md organization
