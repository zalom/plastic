# What Plastic covers

## Commands that exist

| Command | What it does |
| ------- | ------------ |
| `plastic help [COMMAND\|TOPIC] [--json]` | Lists the commands and the help topics, shows one command's usage, or prints one topic. |
| `plastic version` | Prints the installed Plastic version and its release channel. |
| `plastic status` | Lists every store's open and active intents, with node counts by state. |
| `plastic next` | Picks the intent in play and offers its next command. |
| `plastic doctor [--harness NAME]` | Checks the installation, the databases and the hooks of this harness, and names each repair. |
| `plastic init [ANSWER]` | Lists the agent harnesses found on this machine and installs Plastic into each one you pick. |
| `plastic install [--reinstall] [--force] [--dry-run]` | Copies the core files into the home and makes the global store. |
| `plastic update [--channel NAME] [--dry-run]` | Moves Plastic to the next version on its channel. |
| `plastic rollback [--version VERSION] [--dry-run]` | Switches back to the previous release, or to a named one this machine has installed. |
| `plastic uninstall [ANSWER] [--dry-run]` | Removes Plastic from each harness you pick, exactly as its install record lists. The home stays. |
| `plastic config`, `config list`, `config get`, `config set` | Reads and writes the settings in `config.yml`. See [Configuration](configuration.md). |
| `plastic hook start`, `hook stop`, `hook end` | The session hooks. The agent harness calls them, not you. |
| `plastic intent new`, `show`, `spec`, `rule`, `revise`, `note`, `approve`, `judge`, `verdict`, `end`, `abandon` | Carries one intent from its first line to its close. See [Intent commands](intent-commands.md). |
| `plastic intent link`, `unlink`, `archive`, `unarchive` | Links an intent to a ref, and archives or restores its folder. |
| `plastic node`, `plastic edge` and `plastic graph` commands | Build and walk the work graph of an intent. See [Intent commands](intent-commands.md). |
| `plastic auto ID`, `plastic intent lock status ID`, `plastic intent brief ID`, `plastic session note TEXT` | Serves an auto team and writes the prose line of a session. See [Auto and session commands](auto-and-session-commands.md). |
| `plastic project new`, `list`, `links` | Registers a project, lists the projects, and lists broken links. See [Project and roadmap commands](project-and-roadmap-commands.md). |
| `plastic roadmap new`, `batch`, `add`, `show`, `next`, `open`, `drop`, `check`, `log`, `edge remove` | Writes and reads a roadmap. See [Project and roadmap commands](project-and-roadmap-commands.md). |
| `plastic search TERMS`, `plastic document get`, `plastic document batch` | Searches selected stores and fetches immutable evidence. See [Search commands](search-commands.md). |
| `plastic intent discover`, `plastic intent context` | Records retrieval candidates and selected agent context. |
| `plastic architecture status`, `plastic architecture refresh` | Tells the agent to check or regenerate the architecture map with a tool it chooses, such as Enola. |
| `plastic backup --store SLUG` | Copies the three databases of one store into a new backup folder, with `list`, `purge` and `restore`. See [Backup command](backup-command.md). |
| `plastic sync up`, `plastic sync down` | Reads the files changed by hand into rows, and writes the rows that changed into files. See [Sync commands](sync-commands.md). |

## What stays with the agent

The commands print the state and the rules. The judgment stays with the agent: what the
intent is for, what the specification says, and whether the work is done. The auto team runs
as agents that your harness spawns; `plastic auto` serves them the lock, the brief and the
report rules.

Plastic ships no release command. The repository publishes from its branches.
