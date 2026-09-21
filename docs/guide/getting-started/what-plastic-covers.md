# What Plastic covers

## Commands that exist

| Command | What it does |
| ------- | ------------ |
| `plastic help [COMMAND] [--json]` | Lists the commands, or shows one command's usage. |
| `plastic version [--json]` | Prints the installed Plastic version. |
| `plastic status [--json]` | Shows active work in every store. |
| `plastic continue [--project SLUG] [--json]` | Shows where one project stands and what runs next. |
| `plastic next [--why] [--project SLUG] [--json]` | Prints the next action in one line. |
| `plastic install [--claude] [--codex] [--hermes] [--all]` | Installs Plastic into this machine's agents. |
| `plastic update [--claude] [--codex] [--hermes] [--all]` | Moves Plastic to the next version on its channel. |
| `plastic rollback [--version VERSION]` | Moves to a Plastic version this machine has run before. |
| `plastic uninstall [--claude] [--codex] [--hermes] [--all]` | Removes Plastic from this machine's agents. |
| `plastic intent new`, `show`, `spec`, `rule`, `note`, `step`, `answer`, `verify`, `end` | Carries one intent from its first line to its close. See [Intent commands](intent-commands.md). |

## Commands that are planned

These commands do not exist yet. The batch numbers come from the CLI and RLM roadmap.

| Command | Batch | Intent |
| ------- | ----- | ------ |
| `plastic search`, `plastic query` | 3 | 368 |
| `plastic backup` | 3 | 366 |
| A command that moves the stores under `stores/` | 3 | 370 |

## What stays with the agent

The commands print the state and the rules. The judgment stays with the agent: what the
intent is for, what the specification says, and whether the work is done. The auto team, the
dashboard, the doctor and the roadmap still run as Plastic skills. Intent 372 moves them to
commands, one family at a time.

Plastic ships no release command. The repository publishes from its branches.
