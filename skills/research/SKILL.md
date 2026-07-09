---
name: plastic-research
description: "Research a topic for the active intent. Agent decides shallow vs deep based on scope. Produces reports in the intent's resources/ directory."
user-invocable: true
---

# Research

Investigate a topic related to the active intent. Choose the right depth, produce a cited report.

**Announce at start:** "I'm researching [topic] for intent {id} — {name}."

## Active Intent Gate

Before proceeding, resolve the active intent:

1. **Detect store:** Read `~/.plastic/projects.yml`, match CWD against registered project paths. If match → project store at `~/.plastic/projects/{slug}/store/`. If no match → global store at `~/.plastic/store/`.
2. **Find active intent:** Read `INDEX.md` from the detected store. Look under `## Active`. If exactly one → use it. If multiple → ask which. If none → refuse: "No active intent. Create one first with /plastic-creating-intent"
3. **Resolve intent directory:** `{store}/store/{id}--{slug}/`

## Check Prior Work First

QMD-first (when available): before scanning the store with grep/Read or searching the web, run
`ruby ~/.plastic/scripts/qmd-sync search "<terms>"` to surface candidate, prior, or related intents
and existing research, then open the authoritative intent file for any hit you act on. Reusing a
prior report beats re-deriving it. The command is a no-op when QMD is absent, so fall back to the
existing INDEX.md / file scan.

## Depth Decision

Before starting research, assess the question against these criteria:

### Shallow Research
Use when:
- The question is narrow and factual (e.g., "what's the API for X?", "does library Y support Z?")
- A single source or quick search is sufficient
- The answer is likely well-documented
- Time budget: minutes, not hours

**Method:** Direct web search + codebase exploration + single-pass synthesis.

### Deep Research
Use when:
- The question needs multiple sources and cross-verification
- It's a landscape survey, competitive analysis, or architectural decision
- The user explicitly asks for thorough/exhaustive/comprehensive research
- Conflicting information exists and needs adversarial verification
- Time budget: significant, user expects depth

**Method:** Delegate to the native agent's deep research capability.
- On Claude Code: invoke the `deep-research` skill via `Skill` tool
- On other agents: use the agent's equivalent (see intent 7 for cross-agent mapping)
- If no native deep research exists: fan out multiple web searches manually, cross-reference, synthesize

### Decision Heuristic

Ask yourself:
1. Can I answer this with 1-2 searches? → **Shallow**
2. Do I need to compare 3+ sources? → **Deep**
3. Is the user asking for a survey or landscape view? → **Deep**
4. Am I fact-checking a specific claim? → **Shallow**
5. Could wrong information here cause architectural mistakes? → **Deep**

Announce your choice: "This needs [shallow/deep] research because [reason]."

## Output

### File Location
`{intent_dir}/resources/{type}--{topic}.md`

Create the resources/ directory if it doesn't exist.

### Naming Convention
- `{type}` — one of: `deep-research`, `competitive-analysis`, `technical-spike`, `reference`, `landscape-survey`
- `{topic}` — kebab-case description of the research subject

Examples:
- `deep-research--installer-patterns.md`
- `technical-spike--sqlite-vec-performance.md`
- `reference--claude-code-hooks-api.md`
- `landscape-survey--ai-agent-ecosystem.md`

### Report Structure

Default to tabular-first per `PLASTIC.md` (## Tabular-First Reporting, intent 160): tables for findings and comparisons, prose for simple summaries.

```markdown
# {Type}: {Topic}

**Intent:** {id} — {name}
**Depth:** shallow | deep
**Date:** YYYY-MM-DD

## Summary
[2-3 sentence executive summary]

## Findings

### [Finding 1 title]
[Details with inline citations where applicable]

### [Finding 2 title]
...

## Sources
- [Source 1 title](url) — what was learned from this source
- [Source 2 title](url) — ...

## Relevance to Intent
[How these findings affect the active intent's decisions or design]
```

## After Research

1. Commit to store repo:
   ```
   cd {store_root} && git add . && git commit -m "research: {type} — {topic} (intent {id})"
   ```

2. Log in intent's `## Insights`:
   ```
   - Research: {type} — {topic}. Key finding: [one sentence]. See resources/{filename}.
   ```

3. Research does NOT chain to any other skill. It's a side quest — the user decides what to do with the findings.
