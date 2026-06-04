# Plastic

> Intent-driven state management for AI coding sessions.
> Named after **neuroplasticity** — adaptive, malleable, dynamic, resilient.

## What Is This?

Plastic implements two nested processes: **Build → Observe → Repeat** (Coordinator's continuous loop) and **What → Why → How → Next** (intent's finite lifecycle). Zettelkasten-inspired linking connects intents. All project state lives in `.plastic/`. Everything is an intent.

## Installation

### 1. Register the marketplace

In Claude Code, run:
```
/plugin marketplace add zalom/plastic
```

### 2. Install the plugin

In Claude Code, run:
```
/plugin add plastic@plastic
```

### 3. Initialize in your project

In Claude Code, run:
```
/plastic:install
```

## Global vs Local

**Global (recommended):** Plastic stores all intents at `~/.plastic/`. Projects spawned by implementation intents get their own `.plastic/store/` for tactical intents.

```
/plastic:install
```

**Local (testing):** Intents stored per-project in `.plastic/`. Useful for trying Plastic in a single project.

```
/plastic:install --local
```

## Prerequisites

Plastic hooks use Ruby for intent ID generation. Ruby is pre-installed on macOS/Linux. On Windows, use WSL or install Ruby from https://rubyinstaller.org/.

## Directory Structure

```
.plastic/
├── AGENTS.md           # Conventions contract for all agents
├── config.yml          # Plugin configuration
├── INDEX.md            # Brain's entry point
└── store/
    └── ID--three-to-five-words/
        ├── {ID}--{slug}.md         # Always present (e.g., 1a1--design-plastic.md)
        ├── spec.md         # Optional (brainstorming output)
        ├── plan.md         # Optional (implementation plan)
        ├── checklist.md    # Optional (progress tracking)
        └── savepoint.md    # Optional (session state)
```

## Skills

| Skill | Purpose |
|-------|---------|
| `install` | Initialize `.plastic/` in a new project |
| `creating-intent` | Create a new intent with directory, hash, and INDEX.md entry |
| `savepoint` | Save active intent state before context reset |
| `continuing` | Resume from savepoint after `/clear` |
| `linking-intents` | Connect intents via Zettelkasten links |
| `managing-index` | Curate INDEX.md structure note |
| `executing-plan` | Execute plans via subagent-driven (default) or inline mode |

## Agents

| Agent | Purpose |
|-------|---------|
| `intent-curator` | Maintains INDEX.md health, suggests links |
| `future-intent-researcher` | Researches parked future intents |

## License

MIT
