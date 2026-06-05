---
name: plastic:linking-intents
description: Use when creating connections between intents, the user says "link" or "connect", or when discovering that two intents are related. Manages sources, chain, and cross-reference links.
---

# Linking Intents

## When to Use
- During intent creation (automatic — ask about related intents)
- User says "link", "connect", "relates to"
- Agent discovers a relationship between intents during work

## Connection Types (Ranked by Strength)

### 1. Direct Links (Strongest)
Explicit wikilinks in the `## Links` section. Bidirectional — add to both intents.

```markdown
## Links
- [[1a]] — research this plan is based on
```

### 2. Sources (Backward)
The `sources` array in frontmatter. What influenced this intent — backward links to parent/prior work:
```yaml
sources: ["1a", "1a2"]
```

### 3. Chain (Forward)
The `chain` array in frontmatter. What this intent spawned — forward links to children/follow-on work:
```yaml
chain: ["1b1", "1b2"]
```

### 4. Tags (Weakest)
Shared tags in frontmatter enable filtered discovery. Use `project-<name>` tags for project membership.
```yaml
tags: [plastic, project-reddit-kb]
```

## Workflow

### 1. Identify Intents to Connect
Show existing intents by scanning the store's directory for intent files:
```bash
for dir in $STORE_ROOT/store/*/; do
  f=$(find "$dir" -maxdepth 1 -name "*.md" ! -name "spec.md" ! -name "plan.md" ! -name "checklist.md" ! -name "outcome.md" ! -name "savepoint.md" | head -1)
  [ -n "$f" ] && ruby -ryaml -e '
    data = File.read(ARGV[0]).split("---")[1]
    parsed = YAML.safe_load(data)
    puts "#{parsed["id"]} | #{parsed["intent"]}" if parsed
  ' "$f" 2>/dev/null
done
```

### 2. Choose Connection Type
Ask the user which type of connection:
- **source** — "this was influenced by that" (add to `sources[]`, update `chain[]` on the target)
- **cross-reference** — "these are related" (add wikilink in `## Links` of both intents)

### 3. Apply Connection

**For sources:**
Update frontmatter arrays on both intents:
- Add the parent's ID to the child's `sources` array
- Add the child's ID to the parent's `chain` array

**For cross-references:**
Add a wikilink in the `## Links` section of **both** intents (bidirectional).

### 4. Update INDEX.md Clusters
If both intents share a topic, ensure they're in the same cluster.
