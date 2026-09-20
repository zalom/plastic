# What Plastic covers

## Commands that exist

| Command | What it does |
| ------- | ------------ |
| `plastic help [COMMAND] [--json]` | Lists the commands, or shows one command's usage. |
| `plastic version [--json]` | Prints the installed Plastic version. |
| `plastic status [--json]` | Shows active work in every store. |
| `plastic continue [--project SLUG] [--json]` | Shows where one project stands and what runs next. |
| `plastic next [--why] [--project SLUG] [--json]` | Prints the next action in one line. |
| `plastic install [--claude] [--codex] [--dry-run]` | Installs Plastic into this machine's agents. |
| `plastic update [--dry-run]` | Moves Plastic to the next version on its channel. |
| `plastic rollback [VERSION] [--list]` | Moves to a Plastic version this machine has run before. |
| `plastic uninstall [--dry-run]` | Removes Plastic from this machine's agents. |

## Commands that are planned

These commands do not exist yet. The batch numbers come from the CLI and RLM roadmap.

| Command | Batch | Intent |
| ------- | ----- | ------ |
| `plastic intent new`, `plastic intent spec` and the other intent commands | 2 | 372 |
| `plastic search`, `plastic query` | 3 | 368 |
| `plastic backup` | 3 | 366 |
| A command that moves the stores under `stores/` | 3 | 370 |

## What stays with the agent

Everything else still runs through the Plastic skills: creating an intent, writing a
specification, planning, executing and ending. Intent 372 moves them to commands, one family at
a time.

Plastic ships no release command. The repository publishes from its branches.
