# What Plastic covers

## Commands that exist

| Command | What it does |
| ------- | ------------ |
| `plastic help [COMMAND\|TOPIC] [--json]` | Lists the commands and the help topics, shows one command's usage, or prints one topic. |
| `plastic doctor [--core] [--store WHICH]` | Checks the install and the stores. |
| `plastic feedback "TITLE"` | Saves a problem report from standard input and prints a link that files it. |
| `plastic hook EVENT` | Runs one harness hook event through its launcher and returns the launcher exit status. The agent harness calls it, not you. |
| `plastic version [--json]` | Prints the installed Plastic version. |
| `plastic status [--json]` | Shows active work in every store. |
| `plastic continue [--project SLUG] [--json]` | Shows where one project stands and what runs next. |
| `plastic next [--why] [--project SLUG] [--json]` | Prints the next action in one line. |
| `plastic install [--claude] [--codex] [--hermes] [--all]` | Installs Plastic into this machine's agents. |
| `plastic update [--claude] [--codex] [--hermes] [--all]` | Moves Plastic to the next version on its channel. |
| `plastic rollback [--version VERSION]` | Moves to a Plastic version this machine has run before. |
| `plastic uninstall [--claude] [--codex] [--hermes] [--all]` | Removes Plastic from this machine's agents. |
| `plastic intent new`, `show`, `spec`, `rule`, `note`, `step`, `answer`, `verify`, `end` | Carries one intent from its first line to its close. See [Intent commands](intent-commands.md). |
\1| `plastic auto take`, `brief`, `report`, `lock` and `plastic session summary`, `handoff`, `commit` | Serves an auto team and keeps the day ledger. See [Auto and session commands](auto-and-session-commands.md). |
| `plastic roadmap next`, `show`, `log`, `check` | Reads a roadmap and appends to its ledger. See [Project and roadmap commands](project-and-roadmap-commands.md). |

## Commands that are planned

These commands do not exist yet. The batch numbers come from the CLI and RLM roadmap.

| Command | Batch | Intent |
| ------- | ----- | ------ |
| `plastic search`, `plastic query` | 3 | 368 |
| `plastic backup` | 3 | 366 |
| A command that moves the stores under `stores/` | 3 | 370 |

## What stays with the agent

The commands print the state and the rules. The judgment stays with the agent: what the
intent is for, what the specification says, and whether the work is done. The auto team still
runs as a Plastic skill. Intent 372 moves it to commands.

Plastic ships no release command. The repository publishes from its branches.
