---
name: plastic-project-creating
description: >-
  Create a new project from an implementation intent. Sets up project directory,
  git init, AGENTS.md with founding intent decisions, plastic-install --local,
  tactical mirror, projects.yml registration, and framework scaffolding.
  Use when an implementation intent spawns a project, or manually by user.
user-invocable: true
---

# Creating a Project

## Precondition

An active intent must exist with enough context to define a project — at minimum: name/slug, path, and key decisions from `## Context > ### Decisions`.

## Workflow

### 1. Determine Project Identity

- **Slug:** derived from intent name (kebab-case, 2-4 words) or user-specified
- **Path:** from `~/.plastic/config.yml` `project_roots` (first entry as default), or user-specified
- Confirm path with user before creation

### 2. Create Project Directory

```bash
mkdir -p <project_root>/<slug>
cd <project_root>/<slug>
git init
```

### 3. Run `plastic-install --local`

Invoke `plastic-install --local` in the project directory. This creates:
```
.plastic/
├── store/
├── INDEX.md
└── config.yml
```

### 4. Populate AGENTS.md

Create `AGENTS.md` in the project root from the skeleton in
`references/project-scaffolding.md` ("AGENTS.md skeleton"): read it now and fill in
the project name, governing intent IDs, decisions, and project-specific rules.

### 5. Create Tactical Mirror

Create the first intent in the project's store at `~/.plastic/projects/{slug}/store/`
using the frontmatter, sections, and INDEX.md line in `references/project-scaffolding.md`
("Tactical mirror intent"), including the Hub multi-intent variant if there is more
than one founding intent.

**Directory:** `~/.plastic/projects/{slug}/store/1--{slug}/`
**File:** `~/.plastic/projects/{slug}/store/1--{slug}/1--{slug}.md`

### 6. Register in projects.yml

Read `~/.plastic/projects.yml` and add the entry shown in
`references/project-scaffolding.md` ("projects.yml registration block"). For
Hub-spawned projects, `parent` references the primary founding intent.

### 7. Provision the Project Store

The `provision-project-store` verb is the single source of truth for store
creation. Run it after the project is registered in step 6 (the provisioner
requires registration), and before the QMD step:

```bash
ruby ~/.plastic/scripts/provision-project-store <slug>
```

This ensures `~/.plastic/projects/<slug>/store/` exists with `.gitkeep`, and
writes `INDEX.md` and `project.yml` only if missing. It is idempotent, so it is
safe even when the tactical mirror in step 5 already created the store directory.
Do not create the store with an inline `mkdir`; the provisioner is the only place
a store is made. For a project that is already registered but store-less, use the
`plastic-doctor` skill's provisioning section instead.

### 8. Mark Global Intent(s) Completed

For each founding intent:

1. Write `## Outcome` in the intent file:
   > "Spawned project `<slug>` at `<path>`. Decisions carried to AGENTS.md. Tactical mirror: `project-<slug>:1`."
2. Write `outcome.md` with full details (all decisions, project path, tactical mirror ID)
3. Update `chain` to include `project-<slug>:1`
4. Move from `## Active` to `## Completed` in `~/.plastic/INDEX.md` (with today's date)

### 9. Framework Scaffolding

If decisions specify a framework, run the appropriate scaffolding command AFTER steps 3-4 (so scaffolding doesn't overwrite Plastic files or AGENTS.md):

| Framework | Command |
|---|---|
| Rails | `rails new <slug> [options from decisions] --skip-git` (skip git — already initialized) |
| Node/npm | `npm init -y` |
| Ruby gem | `bundle gem <slug>` |
| Other | As specified in decisions |

After scaffolding, verify AGENTS.md and `.plastic/` still exist. If scaffolding overwrote them, restore.

### 10. Auto-commit Both Stores

```bash
cd ~/.plastic && git add . && git commit -m "feat: spawn project <slug> from intent <ID>"
cd <project> && git add . && git commit -m "feat: initialize project from intent <ID>"
```

### 11. Register the project store with QMD (optional)

If QMD is installed, register the new project's store as a search collection:

```bash
ruby ~/.plastic/scripts/qmd-sync register --store ~/.plastic/projects/<slug>/store
```

`qmd-sync` no-ops when QMD is absent, so run it unconditionally. This adds the
`plastic-<slug>` collection and indexes it.

### 12. Self-Check with validate-project

Before announcing, verify the spawn actually landed everything it claims to
have created. Run:

```bash
ruby ~/.plastic/scripts/validate-project <slug>
```

If this exits 0, proceed to step 13. If it exits non-zero, STOP: do not
proceed to Announce. Read the `missing:` and error lines it printed to
stderr, fix the named gap(s), for example:

- missing `project.yml` or `INDEX.md` or `store/`: re-run
  `ruby ~/.plastic/scripts/provision-project-store <slug>` (step 7), then
  re-check
- missing project-root `AGENTS.md`: repeat step 4 (populate AGENTS.md at the
  project root, not `~/.plastic/projects/<slug>/`)
- project directory missing on disk: repeat step 2
- not registered in projects.yml: repeat step 6

Re-run `validate-project <slug>` after each fix until it exits 0. Only a
project spawn that passes this self-check moves on to be announced as
created. A spawn that never verifies itself is exactly the bug this step
exists to close (intent 190; the intent-26 spawn shipped with no
`project.yml` and no root `AGENTS.md`, caught only weeks later by a doctor
sweep).

### 13. Announce

Log in `## Insights` of each founding intent:
> "Project `<slug>` created at `<path>`. Tactical mirror: `project-<slug>:1` (autonomous)"

Announce to user:
> "Project `<slug>` created at `<path>`. AGENTS.md populated with [N] decisions from [founding intent IDs]. Tactical mirror `1` is now the active intent in the project store."

## References

- Read `references/project-scaffolding.md` before steps 4-6, for the AGENTS.md skeleton, the tactical mirror intent format, and the projects.yml registration block
- Read `references/hubs-projects.md` for the full hub/project relationship model, project creation flow, and cross-linking conventions
