---
name: creating-intent
description: Use when new work begins, the user expresses a new goal, says "new intent", or no active intent exists for the current task. Creates the intent directory, writes intent.md, and updates INDEX.md.
---

# Creating an Intent

## When to Use
- User starts new work ("build X", "fix Y", "research Z", "explore W")
- No active intent matches the current task
- User explicitly says "new intent" or "create intent"
- An agent discovers a useful future intent during work

## Workflow

### 1. Determine Next ID
Scan `.plastic/store/` for the highest existing ID:
```bash
ls -d .plastic/store/[0-9]*/ 2>/dev/null | sort -t'-' -k1 -n | tail -1 | grep -o '^[^-]*' | sed 's|.plastic/store/||'
```
Increment by 1, zero-pad to 3 digits.

### 2. Generate Hash
Ask the user for the intent name (3-5 words), then generate the hash:
```bash
ruby -r digest -e 'puts Digest::SHA256.hexdigest(ARGV[0]).to_i(16).to_s(36)[0,6]' "intent name words"
```
Or use the cross-platform helper:
```bash
.plastic/plugin/scripts/hash-intent "intent name words"
```

### 3. Determine Intent Properties
Ask or infer from context:
- **intent**: one-line description of desired outcome
- **type**: `implementation` | `exploration` | `decision` | `bug`
- **author**: `human` | `claude-code` | other agent name
- **status**: `active` (default) or `future` (if parking for later)
- **follows**: ID of the intent this continues from (if any)
- **source**: ID of the intent that spawned this (if future intent from active work)
- **tags**: freeform list

### 4. Create Directory and Files
```bash
mkdir -p .plastic/store/NNN--slug-XXXXXX
```
Write `intent.md` using the intent template format:
- YAML frontmatter with all fields
- `## Intent` section with description
- `## Context` section with what the agent needs to know
- Empty `## Build`, `## Observe`, `## Outcome` sections
- `## Links` section with connections to related intents

### 5. Create Optional Artifacts
If type is `implementation`, ask if the user wants:
- `plan.md` — step-by-step implementation plan
- `checklist.md` — working checklist for tracking progress

### 6. Update INDEX.md
- Add to `## Active` section (or `## Future` if status is future)
- Add to appropriate cluster under `## Clusters` (create new cluster if needed)

### 7. Announce
Tell the user: "Created intent NNN — [name]. Status: [active|future]. Ready to work."

## Quick Reference

| Field | Required | Default |
|-------|----------|---------|
| id | yes | next sequential |
| intent | yes | from user |
| status | yes | active |
| type | yes | inferred or asked |
| author | yes | human |
| created | yes | today |
| updated | yes | today |
| follows | no | null |
| source | no | null |
| supersedes | no | null |
| tags | no | [] |
