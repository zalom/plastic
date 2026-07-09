---
name: plastic-store-provisioning
description: >-
  Add an intent store to a project that is already registered in projects.yml
  but has no store on disk. Use when a project is registered but has no store,
  when you need to provision a store, or when doctor reports a missing project
  store (project_store_dir). Thin wrapper around provision-project-store plus an
  optional qmd register step.
user-invocable: false
---

# Add a Project Store

Provision the intent store for a project that is already registered in
`projects.yml` but whose `~/.plastic/projects/{slug}/store/` is missing. This is
the standalone path; `plastic-project-creating` provisions the store for brand
new projects.

The provisioner is the single source of truth for store creation. It is pure
filesystem and idempotent, so re-running is always safe. The project must already
be registered (this skill does not edit `projects.yml`).

## 1. Resolve the slug

The slug is the project's key under `projects` in `~/.plastic/projects.yml`. If
the user names a project, map it to its slug. If the slug is missing from
`projects.yml`, stop: the provisioner requires the project to already be
registered. If ambiguous, list the registered slugs and ask which one.

## 2. Run the provisioner

```bash
ruby ~/.plastic/scripts/provision-project-store <slug>
```

This creates `~/.plastic/projects/<slug>/store/` with `.gitkeep`, writes
`INDEX.md` and `project.yml` only if they are missing, and never clobbers
existing files. An unregistered slug exits non-zero with a clear error and
creates nothing.

## 3. Register with QMD (separate, optional step)

```bash
ruby ~/.plastic/scripts/qmd-sync register --store ~/.plastic/projects/<slug>/store
```

This is the only qmd mutation; the provisioner itself performs none. It no-ops
when qmd is absent, so it is safe to run unconditionally.

## Scope

- Provisioning and qmd registration are two distinct steps. Do not fold qmd into
  the provisioner.
- No `projects.yml` edits, no project-tree edits, no tactical-mirror or
  founding-intent seeding.
