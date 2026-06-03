---
name: plastic:creating-intent
description: Use when new work begins, the user expresses a new goal, says "new intent", or no active intent exists for the current task. Creates intents in the global store (~/.plastic/store/) or in a project's .plastic/store/ depending on context.
---

# Creating an Intent

## When to Use
- User starts new work ("build X", "fix Y", "research Z")
- No active intent matches the current task
- User explicitly says "new intent" or "create intent"
- An agent discovers work needed during implementation

## Determine Tier

**Global intent** (strategic): created when working outside a registered project, or when the user expresses a high-level goal. Stored in `~/.plastic/store/`.

**Project intent** (tactical): created when working inside a registered project directory. Stored in `<project>/.plastic/store/`. Automatically linked to the project's governing intent.

### Detection logic:
1. Read `~/.plastic/projects.yml`
2. Match CWD against registered project paths
3. If match → project intent (tactical)
4. If no match → global intent (strategic)
5. If no global install exists, fall back to local `.plastic/store/`

## Workflow

### 1. Determine Store Location

- **Global:** `~/.plastic/store/`
- **Project:** `<project-path>/.plastic/store/`
- **Legacy local:** `.plastic/store/`

### 2. Determine Folgezettel ID

**Root intent (no parent):**
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/folgezettel-id" "<STORE>"
```

**Branch intent (has parent):**
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/folgezettel-id" "<STORE>" "<parent_id>"
```

Example: if parent is `1a1b1a` and children `1a1b1a1`–`1a1b1a4` exist, returns `1a1b1a5`.

### 3. Determine Intent Properties

Ask or infer from context:
- **intent**: one-line description
- **author**: `human` | `claude-code` | other agent name
- **sources**: array of Folgezettel IDs that influenced this intent (e.g., `["4a1"]`)
- **chain**: starts empty `[]`, populated when this intent spawns others
- **tags**: freeform list (use `project-<name>` for project membership)

Place in `## Active` or `## Future` in INDEX.md (status is convention-derived, not a frontmatter field).

### 4. Create Directory and Files

```bash
mkdir -p <STORE>/ID--slug
```

Write `{ID}.md` using the intent template. For project intents, add the governing intent's ID to `sources` and add `[[global:ID]]` backlink in `## Links`.

### 5. If Implementation Intent Spawns a Project

When the user says "start building" or the plan calls for a new project:

1. Determine project slug from intent name
2. Create project directory in first `project_roots` path (from `~/.plastic/config.yml`):
   ```bash
   mkdir -p <project_root>/<slug>
   cd <project_root>/<slug>
   git init
   mkdir -p .plastic/store
   touch .plastic/store/.gitkeep
   ```
3. Copy `AGENTS.md` template from `${CLAUDE_PLUGIN_ROOT}/templates/agents.md`
4. Register in `~/.plastic/projects.yml`:
   ```yaml
   <slug>:
     path: <full-path>
     parent: "ID"
     registered: <today>
     status: active
   ```
5. Add `project-<slug>` to the intent's `tags` array
6. Auto-commit in both `~/.plastic/` and the new project

### 6. Update INDEX.md

- **Global intents:** update `~/.plastic/INDEX.md`
- **Project intents:** no global INDEX.md change (tactical intents are project-scoped)
- **Legacy local:** update `.plastic/INDEX.md`

Add to `## Active` (or `## Future`) and appropriate cluster.

### 7. Auto-commit

```bash
cd <store-root> && git add . && git commit -m "feat: create intent ID — [name]"
```

### 8. Announce

"Created intent ID — [name]. Placed in: [Active|Future]. Store: [global|project:<slug>|local]."
