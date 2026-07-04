---
name: plastic-linking-intents
description: Use when creating connections between intents, the user says "link" or "connect", or when discovering that two intents are related. Manages sources, chain, and cross-reference links.
---

# Linking Intents

## When to Use
- During intent creation (automatic: ask about related intents)
- User says "link", "connect", "relates to"
- Agent discovers a relationship between intents during work

## Discovery and ranking are separate

Two distinct steps, do not conflate them:

1. **Discovery** (finding candidate related intents) may use any tool: grep, find, ripgrep,
   or QMD/Serena when present (QMD-first per the project rule). Discovery casts a wide net.
2. **Ranking** the candidates is a CONTEXT-INFLUENCE judgement: read each candidate's `## Intent`
   and `## Context` and ask whether that context actually informed this intent. Ranking is NOT a
   structural metric (no shared-file or shared-symbol grading: on intent 90, matching whole files
   flagged 35 intents because ~20 touch `bridge.rb`). It is NOT a similarity score either (QMD
   relevance measures topic proximity, not influence). A script cannot make this call; an agent
   does.

## The three tiers (by context influence)

- **sources:** the foundational context that shaped this intent's CREATION (a split, an idea born
  during development, a merge). Earns an edge. Decided by origin, never inferred.
- **chain:** the context that materially helps DELIVER this intent. HIGH bar: only the genuinely
  delivery-moving intents, not everything in the same area. Earns an edge, reflected in `## Links`.
  Worked example (intent 90): 79 created it so 79 is a source; 80 deferred the exact fix 90 makes,
  so its context directly helps delivery and 80 is chain; 49/66/73 are same-area background, so
  they get a shared tag and no link.
- **tags:** loose theme grouping for search. NOT a link.

**Timing.** The influence judgement happens at What/Why (and during upkeep), guided by this rule.
It does not wait for code to exist; it is reasoning over the candidate's context, not over a diff.

**Record the call.** For every edge an agent adds, store a rating (high / medium / low) plus a
one-line reason as a dated line under the intent file's `## Insights` section (per 96 D3, link
rationale lives in the intent file, not a side file). It stays out of frontmatter (graph only) and
out of the projected `## Links` label, so the audit trail never breaks the projection identity.

## `## Links` is derived (never author it by hand)

`## Links` is a DERIVED view of `sources` then `chain`, not a place to write links. Never
hand-write a `## Links` line, and never auto-delete one. To add a link, add the frontmatter
edge (below), then let the projection regenerate the section (`scripts/project-links`).

Run `scripts/link-suggest <id>` to gather candidate intents WITH each one's Intent and Context (the
evidence you judge influence on) and to flag drift (a `## Links` line with no frontmatter edge
behind it). To record a confirmed edge plus its rating and reason, run it with
`--record <id> --edge <sources|chain> --rating <high|medium|low> --reason "..." --confirm`. It never
grades influence itself, never writes an edge without `--confirm`, and never deletes.

## Connection Types (the frontmatter edges)

### 1. Sources (Backward)
The `sources` array in frontmatter. The direct ascendant(s) this intent was created from / emerged from the lifecycle of (formation, not topic similarity), backward links to the work it was built out of:
```yaml
sources: ["1a", "1a2"]
```

### 2. Chain (Forward)
The `chain` array in frontmatter. What this intent spawned AND related-but-not-spawned successors it leads to, forward links to children, follow-on, and related work:
```yaml
chain: ["1b1", "1b2"]
```

### 3. Tags (for discovery, not links)
Shared tags in frontmatter enable filtered discovery. Use `project-<name>` tags for project membership. A shared tag is a loose theme grouping: it earns NO edge.
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
