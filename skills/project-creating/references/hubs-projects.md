# Hubs and Projects

## Hubs

A Hub is a cloud of intents around related topics. Hubs emerge naturally from
Folgezettel branching — intents that spawn in the same direction cluster.

- A Hub can spawn a Project. The Hub holds the founding ideas.
- A single intent can also spawn a Project.
- Hub-spawned projects revolve around different ideas around related topics.
- Intent-spawned projects revolve around the single founding intent.
- A Project is the deliverable outcome of one or more intents.

Hubs are represented as clusters in INDEX.md.

## Projects — Full Detail

A Project is a deliverable grouping of intents. Projects have two stores:

- **Global store** (`~/.plastic/store/`): strategic intents
- **Project store** (`~/.plastic/projects/{slug}/store/`): tactical intents

`projects.yml` maps project slugs to codebase paths:
```yaml
projects:
  plastic:
    path: "/path/to/plastic"
    remote: "git@github.com:org/plastic.git"
    registered: '2026-05-26'
    status: active
```

Config resolution: `~/.plastic/projects/{slug}/config.yml` overrides `~/.plastic/config.yml`.

Cross-linking: project intents reference global intents via `[[global:ID]]`. Global intents reference project intents via `[[project-slug:ID]]`.

## Privacy and Collaboration

**Plastic is personal.** All intent data lives under `~/.plastic/` — one location,
one git repo, never pushed. Each person has their own intent store.

Collaboration happens through pull requests and project conventions, not shared intents.
When an intent delivers something that changes how a project works, the decision gets
written into the project's shared files (README, docs, config). The intents themselves
are private working memory.

## Project Creation Flow

When an implementation intent spawns a project:
1. Determine project path from config `project_roots` or intent context
2. `gh repo create --private` (agent-created repos are always private by default)
3. Set up project directory, git init, AGENTS.md with founding intent decisions
4. Register in `projects.yml`
5. Create tactical mirror in project store
6. The global intent completes; the tactical mirror becomes the active intent
