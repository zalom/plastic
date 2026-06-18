---
name: plastic-creating-intent
description: Use when new work begins, the user expresses a new goal, says "new intent", or no active intent exists for the current task. Creates intents in the global store (~/.plastic/store/) or in a project's store (~/.plastic/projects/{slug}/store/) depending on context.
---

# Creating an Intent

## When to Use
- User starts new work ("build X", "fix Y", "research Z")
- No active intent matches the current task
- User explicitly says "new intent" or "create intent"
- An agent discovers work needed during implementation

## Determine Tier

**Global intent** (strategic): created when working outside a registered project, or when the user expresses a high-level goal. Stored in `~/.plastic/store/`.

**Project intent** (tactical): created when working inside a registered project directory. Stored in `~/.plastic/projects/{slug}/store/`. Automatically linked to the project's governing intent.

### Detection logic:
1. Read `~/.plastic/projects.yml`
2. **CWD match:** Match CWD against registered project paths
   - If CWD is inside a registered project → **project intent (tactical)**
3. **Explicit mention:** User mentions an existing project by name ("add this to reddit-kb", "new intent for plastic")
   - Look up project in `projects.yml` by slug
   - If found → **project intent (tactical)** in that project's store at `~/.plastic/projects/{slug}/store/`
   - Agent changes working directory to the project path for execution
4. **No match:** CWD is not in a project AND no project mentioned
   - → **global intent (strategic)** in `~/.plastic/store/`

When creating a tactical intent in a project store:
- Read the project's `AGENTS.md` for project context and decisions
- Link back to the project's governing intent (from `projects.yml` `parent` field) via `sources`
- Add `[[global:<parent_ID>]]` backlink in `## Links`
- The intent's Folgezettel ID is scoped to the project store (run `folgezettel-id` against the project's store at `~/.plastic/projects/{slug}/store/`)

## Workflow

### 1. Determine Store Location

- **Global:** `~/.plastic/store/`
- **Project:** `~/.plastic/projects/{slug}/store/`

### 2. Decide Branch vs Root

Decide this BEFORE scaffolding, because it sets whether you pass `--parent`.
Having a "parent" in mind does NOT automatically mean branch. Choose by meaning:

- **Branch (`14a`, `14b`)**: a sub-task, refinement, or direct continuation. It only
  makes sense as part of the parent's work. Pass `--parent <parent_id>`.
- **Root (`15`, `16`)**: an independent thought, even if inspired by another intent.
  Capture the inspiration in `--sources`, not in the id. Omit `--parent`.
- **Rule of thumb:** if the intent could exist without its parent, make it a root and
  set `--sources`. Only branch when it genuinely cannot stand alone.

### 3. Determine Intent Properties

Ask or infer from context:
- **intent**: one-line description
- **slug**: short hyphenated handle for the directory name
- **author**: `human` | `claude-code` | other agent name
- **sources**: Folgezettel ids that influenced this intent (e.g., `4a1`). For a
  project intent, include the governing intent's id.
- **tags**: freeform list (use `project-<name>` for project membership)

`chain` starts empty and is populated later when this intent spawns others.
Place the intent in `## Active` or `## Future` in INDEX.md (status is
convention-derived, not a frontmatter field).

### 4. Scaffold via new-intent (single call)

Delegate id allocation, directory and file creation, the born-complete intent
file, the sentinel placeholder lifecycle files, the reciprocal file links, and
self-validation to one `new-intent` invocation. Do NOT hand-author any of these
files.

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/new-intent" \
  --store "<STORE>" --intent "<one-line>" --slug "<slug>" \
  [--parent "<parent_id>"] [--author "<author>"] \
  [--sources "id,id"] [--tags "project-<slug>,tag"]
```

`new-intent` allocates the Folgezettel id (root, or a branch of `--parent`),
creates `<STORE>/<id>--<slug>/` plus `actions/` and `resources/`, renders the
born-complete `<id>--<slug>.md` from the intent template, writes the sentinel
placeholder `spec.md`/`plan.md`/`checklist.md`/`outcome.md` (each marked
`<!-- plastic:placeholder -->` so no stage detector reads them as reached), wires
the reciprocal `[[id]]` links, and self-validates (frontmatter plus the sanctioned
`##` sections). It prints the created directory path and exits 0.

It does NOT touch INDEX.md, git, or project creation: those stay in this skill
(steps 6 to 9 below).

If `new-intent` exits non-zero, read the stderr report and fix the inputs (slug,
intent, sources). Do not commit or announce an intent that did not scaffold
cleanly, and do not work around the failure by hand-writing the files.

### 6. If Implementation Intent Spawns a Project

When the user says "start building" or the plan calls for a new project:

1. Determine project slug from intent name
2. Create project directory in first `project_roots` path (from `~/.plastic/config.yml`):
   ```bash
   mkdir -p <project_root>/<slug>
   cd <project_root>/<slug>
   git init
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
5. Provision the project store (the single source of truth for store creation;
   runs after step 4 because the provisioner requires the project to be
   registered):
   ```bash
   ruby ~/.plastic/scripts/provision-project-store <slug>
   ```
6. Add `project-<slug>` to the intent's `tags` array
7. Auto-commit in both `~/.plastic/` and the new project

### 7. Update INDEX.md

- **Global intents:** update `~/.plastic/INDEX.md`
- **Project intents:** no global INDEX.md change (tactical intents are project-scoped)

Add to `## Active` (or `## Future`) and appropriate cluster.

### 8. Auto-commit

```bash
cd <store-root> && git add . && git commit -m "feat: create intent ID - [name]"
```

### 9. Announce

"Created intent ID - [name]. Placed in: [Active|Future]. Store: [global|project:<slug>|local]."

## References

- Read `references/lifecycle.md` for the full What→Why→How→Exec stage detail, filesystem-as-schema conventions, and creating-intent step-by-step
- Read `references/wikilinks.md` for the wikilink syntax table when adding `## Links` to intents
