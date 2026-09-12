---
name: plastic-intent-creating
description: Use when new work begins, the user expresses a new goal, says "new intent", or no active intent exists for the current task. Creates intents in the global store (~/.plastic/store/) or in a project's store (~/.plastic/projects/{slug}/store/) depending on context.
user-invocable: true
---

# Creating an Intent

Creating writes the thought to disk: an id, a directory, a born-complete intent file.
Nothing else runs here; specifying, planning, and execution are separate, later skills.

## When to use
- User starts new work ("build X", "fix Y", "research Z")
- No active intent matches the current task
- User explicitly says "new intent" or "create intent"
- An agent discovers work needed during implementation

## Decide the store and the shape, before scaffolding

- **CWD inside a registered project** (`~/.plastic/projects.yml`), or the user names a
  project by slug -> **project intent (tactical)**, `~/.plastic/projects/{slug}/store/`,
  linked back to the project's governing intent (`projects.yml` `parent` field) via
  `sources`, with `[[global:<parent_ID>]]` in `## Links` and a Folgezettel id scoped to
  that store.
- **No match** -> **global intent (strategic)**, `~/.plastic/store/`.
- **Duplicate or predecessor check (QMD-first):** before allocating an id, run
  `ruby ~/.plastic/scripts/qmd-sync search "<terms>"` (a no-op when QMD is absent, fall
  back to INDEX.md) so a near-duplicate is reused and a true predecessor lands in
  `--sources`.
- **Branch vs root**, decided by meaning, not by "a parent in mind": branch
  (`--parent <parent_id>`) when the intent only makes sense as part of the parent's work;
  root with `--sources <ascendant_id>` when it was created from another intent's
  lifecycle; root with no `--sources` when it is merely related (record that relation on
  the PREDECESSOR's `chain` instead - topic similarity alone is never a `sources` edge).

When a branch intent exists because a late ruling arrived AFTER its parent was already
completed, the parent is restored to v1 via `scripts/restore-intent-v1`, never a hand-run
`git checkout`/revert (see `plastic-conventions > references/maintenance-and-revisions.md`,
WORK vs MAINTENANCE).

`## Links` is a DERIVED view of `sources`/`chain`: never hand-write a `## Links` line, add
the frontmatter edge and reproject. Links follow context influence (a `chain` edge needs
the candidate's context to materially help deliver this intent), never shared files or a
similarity score; `scripts/link-suggest` and `scripts/project-links` gather candidates.
Read `../plastic-conventions/references/knowledge-graph.md` for the full linking doctrine:
the tiers of influence, sources versus chain, and how `## Links` is derived.

## Scaffold

One call does the rest: id allocation, the directory, `actions/` and `resources/`, the
born-complete intent file, sentinel placeholder lifecycle files (each marked
`<!-- plastic:placeholder -->` so no stage detector reads them as reached), reciprocal
`[[id]]` links, and self-validation. Do NOT hand-author any of these files.

```bash
ruby ~/.plastic/scripts/new-intent \
  --store "<STORE>" --intent "<one-line>" --slug "<slug>" \
  [--parent "<parent_id>"] [--author "<author>"] \
  [--sources "id,id"] [--tags "project-<slug>,tag"]
```

It does NOT touch INDEX.md, git, or project creation (Finish, below). If it exits
non-zero, read the stderr report, fix the inputs (slug, intent, sources), and retry;
never work around a failed scaffold by hand-writing the files.

`chain` carries what this intent spawns AND related-but-not-spawned successors it leads
to; it starts empty and is populated later. See
[`how-plastic-sources-and-chains-intents.md`](https://github.com/zalom/plastic/blob/main/docs/concepts/how-plastic-sources-and-chains-intents.md)
for the full model.

## Finish

1. **Global intent:** add a line to `~/.plastic/INDEX.md` under `## Active` (or
   `## Future`) and the right cluster. **Project intent:** no global INDEX.md change.
2. When the user says "start building" or the plan calls for a new project, invoke
   `plastic-project-creating`; it owns project directory creation, AGENTS.md population,
   `projects.yml` registration, store provisioning, and the auto-commit of both stores.
   Add `project-<slug>` to this intent's `tags` either before invoking it or as part of
   that skill's handoff.
3. Commit: `cd <store-root> && git add . && git commit -m "feat: create intent ID - [name]"`.
4. Announce: "Created intent ID - [name]. Placed in: [Active|Future]. Store:
   [global|project:<slug>]."

## References

- Read `references/lifecycle.md` for the full What->Why->How->Exec stage detail and the
  filesystem-as-schema conventions.
- Read `references/wikilinks.md` for the wikilink syntax table when hand-checking a
  `## Links` projection.
