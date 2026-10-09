# What Plastic covers

## Commands that exist

| Command | What it does |
| ------- | ------------ |
| `plastic help [COMMAND\|TOPIC] [--json]` | Lists the commands and the help topics, shows one command's usage, or prints one topic. |
| `plastic doctor [--store WHICH]` | Checks the install and the stores. |
| `plastic feedback "TITLE"` | Saves a problem report from standard input and prints a link that files it. |
| `plastic hook EVENT` | Runs one harness hook event through its launcher and returns the launcher exit status. The agent harness calls it, not you. |
| `plastic version [--json]` | Prints the installed Plastic version. |
| `plastic status [--json]` | Shows active work in every store. |
| `plastic graph resume [--stores a,b] [--json]` | Shows where each named project's work stopped and what runs next. |
| `plastic next [--why] [--project SLUG] [--json]` | Prints the next action in one line. |
| `plastic install [--claude] [--codex] [--hermes] [--all]` | Installs Plastic into this machine's agents. |
| `plastic update [--claude] [--codex] [--hermes] [--all]` | Moves Plastic to the next version on its channel. |
| `plastic rollback [--version VERSION]` | Moves to a Plastic version this machine has run before. |
| `plastic uninstall [--claude] [--codex] [--hermes] [--all]` | Removes Plastic from this machine's agents. |
| `plastic intent new`, `show`, `spec`, `rule`, `note`, `step`, `answer`, `verify`, `end` | Carries one intent from its first line to its close. See [Intent commands](intent-commands.md). |
| `plastic auto`, `plastic intent lock status`, `plastic intent brief` and `plastic session summary`, `handoff`, `commit` | Serves an auto team and keeps the day ledger. See [Auto and session commands](auto-and-session-commands.md). |
| `plastic project new`, `list`, `links` | Registers a project, lists the stores, and rebuilds the Links sections. See [Project and roadmap commands](project-and-roadmap-commands.md). |
| `plastic roadmap next`, `show`, `log`, `check`, `migrate` | Reads a roadmap, appends to its ledger, and writes a missing Graph section. See [Project and roadmap commands](project-and-roadmap-commands.md). |
| `plastic search TERMS`, `plastic document get`, `plastic document batch` | Searches selected stores and fetches immutable evidence. See [Search commands](search-commands.md). |
| `plastic intent discover`, `plastic intent context` | Records retrieval candidates and selected agent context. |
| `plastic architecture status`, `plastic architecture refresh` | Tells the agent to check or regenerate the architecture map with a tool it chooses, such as Enola. Plastic also asks for the map before planning and again in `plastic intent end`. |
| `plastic backup --store SLUG` | Copies the three databases of one store into a UTC-named folder, with `list`, `purge` and `restore`. See [Backup command](backup-command.md). |
| `plastic migrate stores [--dry-run]` | Moves every store under `~/.plastic/stores/`, after a copy of the home. See [Migrate command](migrate-command.md). |
| `plastic sync [--dry-run]`, `plastic checkout` | Writes the stores into the three databases, and writes the databases back out as files. See [Sync commands](sync-commands.md). |
| `plastic render FILE` | Renders one Markdown file as a styled HTML page. |

## What stays with the agent

The commands print the state and the rules. The judgment stays with the agent: what the
intent is for, what the specification says, and whether the work is done. The auto team runs
as agents that your harness spawns; `plastic auto` serves them the lock, the brief and the
report rules.

Plastic ships no release command. The repository publishes from its branches.
