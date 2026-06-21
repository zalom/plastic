---
name: plastic-linking-intents
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
The `sources` array in frontmatter. The direct ascendant(s) this intent was created from / emerged from the lifecycle of (formation, not topic similarity), backward links to the work it was built out of:
```yaml
sources: ["1a", "1a2"]
```

### 3. Chain (Forward)
The `chain` array in frontmatter. What this intent spawned AND related-but-not-spawned successors it leads to, forward links to children, follow-on, and related work:
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

QMD-first (when available): before scanning the store with grep/Read, run
`ruby ~/.plastic/scripts/qmd-sync search "<terms>"` to surface candidate, prior, or related
intents to propose as sources/chain, then open the authoritative intent file for any hit you act
on. The command is a no-op when QMD is absent, so fall back to the directory scan below.

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
- **source**: "this was CREATED FROM that" (D1). The reciprocal update is one-directional (I1): add the ascendant id to this intent's `sources[]` AND add this intent's id to the ascendant's `chain[]`. A merely-related (not-created-from) connection is NOT a source: record it on the predecessor's `chain[]` only, plus a `## Links` wikilink, with NO `sources` (the related-but-not-spawned rule).
- **cross-reference**: "these are related" (add wikilink in `## Links` of both intents)

### 3. Apply Connection

**For sources (a true created-from edge only):**
Update frontmatter arrays on both intents (I1, two-sided):
- Add the parent's ID to the child's `sources` array
- Add the child's ID to the parent's `chain` array

For the merely-related case, only the predecessor's `chain` (and both sides' `## Links`)
get the link, never `sources`. `chain` is NOT strictly the reverse of `sources` (I2):
relational `chain` entries are valid and must never be "corrected" by adding a reciprocal
`sources`.

**For cross-references:**
Add a wikilink in the `## Links` section of **both** intents (bidirectional).

### 4. Update INDEX.md Clusters
If both intents share a topic, ensure they're in the same cluster.

## References

- Read `references/zettelkasten.md` for the three Zettelkasten structures (Folgezettel, directed graph, tags), ID encoding rules, and dual-mode (Obsidian + programmatic) design
