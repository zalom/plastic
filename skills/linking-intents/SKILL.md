---
name: linking-intents
description: Use when creating connections between intents, the user says "link" or "connect", or when discovering that two intents are related. Manages follows, source, supersedes, and cross-reference links.
---

# Linking Intents

## When to Use
- During intent creation (automatic — ask about related intents)
- User says "link", "connect", "relates to"
- Agent discovers a relationship between intents during work

## Connection Types (Ranked by Strength)

### 1. Direct Links (Strongest)
Explicit markdown links in the `## Links` section. Bidirectional — add to both intents.

```markdown
## Links
- [Research Reddit saved posts](../001--research-reddit-saved-posts-3k8gyi/intent.md) — research this plan is based on
```

### 2. Sequence (Folgezettel)
The `follows` field in frontmatter. One intent continues from another:
```yaml
follows: "001"
```

### 3. Source
The `source` field. A future intent spawned from active work:
```yaml
source: "003"
```

### 4. Supersedes
The `supersedes` field. A new intent replaces an older one:
```yaml
supersedes: "002"
```

### 5. Tags (Weakest)
Shared tags in frontmatter enable filtered discovery.

## Workflow

### 1. Identify Intents to Connect
Show existing intents by scanning `.plastic/store/*/intent.md` frontmatter:
```bash
for f in .plastic/store/*/intent.md; do
  ruby -ryaml -e '
    data = File.read(ARGV[0]).split("---")[1]
    parsed = YAML.safe_load(data)
    d = File.dirname(ARGV[0]).split("/").last
    puts "#{parsed["id"]} | #{parsed["status"].to_s.ljust(9)} | #{parsed["intent"]}" if parsed
  ' "$f" 2>/dev/null
done
```

### 2. Choose Connection Type
Ask the user which type of connection:
- **follows** — "this continues from that"
- **source** — "this was spawned from that"
- **supersedes** — "this replaces that"
- **cross-reference** — "these are related but independent"

### 3. Apply Connection
**For frontmatter fields** (follows, source, supersedes):
Update the YAML frontmatter of the appropriate intent.

**For cross-references:**
Add a markdown link in the `## Links` section of **both** intents (bidirectional).

### 4. Update INDEX.md Clusters
If both intents share a topic, ensure they're in the same cluster.
