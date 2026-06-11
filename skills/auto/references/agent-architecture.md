# Agent Architecture

## Main Orchestrator

The Main Orchestrator manages the global store (Main Knowledge Base). It:
- Recognizes, creates, updates, and groups intents
- Spawns Project Orchestrators for registered projects
- Receives contributions back from Project Orchestrators
- Is the only agent that runs in a loop (continuous Build→Observe→Repeat)

## Project Orchestrators

Project Orchestrators manage project stores (Project Knowledge Bases). They:
- Care about intents and execution within their project
- Spawn teams to develop and execute intents
- Contribute back to the Main Orchestrator when new intents are born
  that could enrich the Main Knowledge Base

Rules:
- 1 Main Orchestrator : 1 Global Store (`~/.plastic/`)
- 1 Main Orchestrator : N Project Orchestrators
- 1 Project Orchestrator : 1 Project Store
- 1 Agent : 1 Intent (exclusive assignment)
- 1 Agent : N Sub-agents (for parallel Actions within an intent)

## Two Modes

- **Human-driven:** Human chats with Main Orchestrator, creates intents,
  brainstorms, then Main Orchestrator dispatches Project Orchestrators and
  Agents for execution.
- **Autonomous:** Human gives Main Orchestrator a starting intent with defined
  outcomes. Main Orchestrator runs the full cycle — Agents do the lifecycle
  (What→Why→How→Exec), Main Orchestrator reviews Insights, spawns next intents,
  dispatches again.

## Autonomous Delivery

Human owns What and Why for human-initiated intents. Agent assists (research,
exploration) but human drives until handoff. When Why is complete — or human
triggers `plastic-auto` — the agent takes over How and Exec autonomously.

- **Safe-by-default:** Agent always prefers non-destructive routes (rename vs
  delete, additive migrations, backups before changes). Destructive actions on
  existing projects require human approval unless `--skip-permissions` is set.
- **One agent per intent.** Agent follows the full W→W→H→E lifecycle.
- **Notification only on:** finish or hard stop (blocked on destructive action,
  unresolvable error). No progress reports — `## Insights` tracks everything.
- **Greenfield autonomy:** During initial project creation, all decisions are
  non-destructive (nothing to destroy). Agent has full autonomy for greenfield choices.
- **Autonomous decisions** are logged in `## Insights` with `(autonomous)` marker.

## Coordinator Loop

When "work on Project X":
1. Read `projects.yml` → find project path
2. Load global config (defaults)
3. Load project config (overrides)
4. Load global INDEX.md → find hub intents tagged `project-<name>`
5. Load project INDEX.md → tactical intents
6. Coordinator has full picture, dispatches Agent teams
