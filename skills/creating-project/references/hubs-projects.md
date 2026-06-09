# Hubs and Projects

## Hubs

A Hub is a cloud of intents around related topics. Hubs emerge naturally from
Folgezettel branching — intents that spawn in the same direction (same concept,
new ideas, new features) cluster into a Hub.

- A Hub can spawn a Project. The Hub holds the founding ideas.
- A single intent can also spawn a Project (Intent-spawned vs Hub-spawned).
- Hub-spawned projects revolve around different ideas/features around related topics.
- Intent-spawned projects revolve around the single founding intent.
- A Project is the result of ideation — the deliverable outcome of one or more intents.

Hubs are represented as clusters in INDEX.md.

## Projects

A Project is a deliverable grouping of intents — a hub that connects related work
into something that can be delivered. Projects have two stores, both under `~/.plastic/`:

- **Global store** (`~/.plastic/store/`): strategic intents — ideas, research,
  explorations that span multiple projects or don't belong to any project.
- **Project store** (`~/.plastic/projects/{slug}/store/`): project-scoped intents —
  implementation, actions, execution, delivery artifacts.

No files are placed in project code directories. The SessionStart hook detects the
project by matching CWD against `projects.yml` and loads the appropriate store.

### projects.yml

Maps project slugs to codebase paths:

```yaml
projects:
  plastic:
    path: "/path/to/plastic"
    remote: "git@github.com:org/plastic.git"
    registered: '2026-05-26'
    status: active
```

The project store path is always derived: `~/.plastic/projects/{slug}/store/`.
No explicit store path in `projects.yml`.

### Config Resolution

`~/.plastic/projects/{slug}/config.yml` overrides `~/.plastic/config.yml`.
Both are private.

### Cross-Linking

Project intents reference global intents via `[[global:ID]]`.
Global intents reference project intents via `[[project-slug:ID]]`.

### Privacy

**Plastic is personal.** All intent data lives under `~/.plastic/` — one location,
one git repo, never pushed. Each person has their own intent store with their own
thought evolution. No files are placed in project directories.

Collaboration happens through pull requests and project conventions, not shared intents.
