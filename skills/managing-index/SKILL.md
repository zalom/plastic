---
name: plastic:managing-index
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
- [003 — Design Plastic](store/003--design-plastic-state-system-wigjln/intent.md) — decision, human
```

### Future
Intents parked for later. May be picked up by agents.
```markdown
## Future
- [006 — Build Reddit KB](store/006--build-reddit-knowledge-base-2yv12k/intent.md) — implementation, human
```

### Clusters
Topic-based groupings. Manually curated. Create a new cluster when 3+ intents share a topic.
```markdown
## Clusters
### Reddit Knowledge Base
- [001 — Research](store/001--research-reddit-saved-posts-3k8gyi/intent.md)
- [002 — Plan](store/002--plan-reddit-knowledge-base-324trd/intent.md)
```

### Completed
All completed intents with dates. Links preserved, never deleted.

## Workflow

### Rebuild Sections
Scan `.plastic/store/*/intent.md` frontmatter and rebuild each section:

```bash
for f in .plastic/store/*/intent.md; do
  dir=$(dirname "$f" | xargs basename)
  ruby -e '
    data = File.read(ARGV[0]).split("---")[1]
    parsed = YAML.safe_load(data)
    puts "#{parsed["status"]}|#{parsed["id"]}|#{parsed["intent"]}|#{ARGV[1]}"
  ' "$f" "$dir" 2>/dev/null
done | sort -t'|' -k2
```

### Suggest Clusters
When 3+ intents share tags but aren't in a cluster, suggest a new cluster heading.

### Flag Orphans
Intents with no links (no `follows`, no `source`, no `## Links` entries, not in any cluster) should be flagged for curation.

REQUIRED BACKGROUND: linking-intents (for understanding connection types and Zettelkasten theory)
