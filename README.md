<h1 align="center">
  <img src="https://raw.githubusercontent.com/zalom/plastic/main/assets/plastic-logo.svg"
    alt="Plastic" width="360">
</h1>

<p align="center">
  <strong>One command that turns an intent into a durable, linked record of decisions, plans, delivery and outcomes</strong>
</p>

<p align="center">
  <a href="https://github.com/zalom/plastic/actions/workflows/test.yml"><img src="https://github.com/zalom/plastic/actions/workflows/test.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/zalom/plastic/releases"><img src="https://img.shields.io/github/v/release/zalom/plastic" alt="Release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/zalom/plastic" alt="License: MIT"></a>
</p>

<p align="center">
  <a href="#installation">Install</a> &bull;
  <a href="#quick-start">Quick start</a> &bull;
  <a href="#commands">Commands</a> &bull;
  <a href="docs/guide/getting-started/troubleshooting.md">Troubleshooting</a> &bull;
  <a href="docs/contributing/ARCHITECTURE.md">Architecture</a> &bull;
  <a href="MANIFESTO.md">Manifesto</a>
</p>

---

Plastic is an intent-based system for AI-assisted work. You do not always start with a task.
You start with an intent, such as "I want users who are locked out to recover access safely."
Plastic carries that intent through four stages, What, Why, How and Exec, and leaves a
readable record of how the idea became real.

Plastic is named after neuroplasticity, the brain's ability to change as it learns.

## What Plastic does

Plastic keeps the shape of the work fixed and leaves the thinking to you and your agent.

| You want to | What Plastic does |
|-------------|-------------------|
| Start from a rough idea | Creates one intent directory with an id, a slug and a born-complete intent file |
| Keep the reasons | Appends each ruling to the Insights section of the intent file |
| Plan the work | Holds the plan as a checklist or as a graph of nodes, and names the next step |
| Resume tomorrow | Prints where a project stands and the next action in one line |
| Hand work to an agent team | Arms a delivery lock, briefs each role and reports the result |
| Close the work | Checks the merge and the records, fills placeholder records, and moves the intent to Completed or Abandoned |
| Find an old decision | Searches every store, ranked, with one excerpt for each match |
| Run many projects | Keeps one store for each project, plus a global store, all in plain Markdown and Git |
| Steer a long delivery | Reads a roadmap as a graph and names the entry most worth continuing |
| Protect the record | Writes one archive of the three databases, as of the last `plastic sync up`, with `config.yml`, `projects.yml`, and `INDEX.md` |

Every result ends with a `next:` line and a `because:` line. The `--json` option prints the
same result as data with stable keys. Every command takes it except the installer commands
(`install`, `update`, `uninstall`, `rollback`) and `plastic hook EVENT`, which runs a hook
script for the harness.

## How the record is built

Each intent is one directory. Its record grows from the original intention through decisions,
a plan, and delivery. The execution plan can use a checklist or a graph of dependent nodes.

| Stage | Question | File on disk |
|-------|----------|--------------|
| What | What is the intention? | `{id}--slug.md` |
| Why | What context, evidence, and decisions shape it? | `spec.md` |
| How | What is the plan? | `plan.md`; `checklist.md` and `actions/`, or `graph.md` and `nodes/` |
| Exec | What happened, and what was delivered? | `savepoint.md`, `outcome.md` |

For graph work, `graph.md` links nodes by their dependencies, and `nodes/` holds the
instructions for each node. Plastic uses those dependencies and the node transitions in
`savepoint.md` to determine which work is ready. `plastic next` names the next
graph step once the session holds the delivery lock. For checklist work, the same command
reports the next unfinished item.

The files are plain Markdown in a Git repository that you own. See
[the architecture](docs/contributing/ARCHITECTURE.md) for the full store layout.

## Installation

Plastic needs curl, tar, and `sha256sum` or `shasum`. `install.sh` brings its own Ruby 4.0.7.
It runs on macOS, and on Linux with glibc 2.29 or later. Alpine and other musl systems
are not supported. On Windows, install Plastic inside WSL; there is no native Windows install.

```bash
curl -fsSL https://raw.githubusercontent.com/zalom/plastic/main/install.sh | sh
plastic init
```

`install.sh` downloads Ruby 4.0.7 for your platform and checks it by its pinned size and SHA-256.
It then downloads the newest stable release, checks it against its published checksum, and links
`~/.local/bin/plastic`. The Bundler of that Ruby installs the sqlite3 and tty-prompt gems inside each release.
`plastic init` lists the agent harnesses it finds, Claude Code and Codex CLI, each one picked,
and installs Plastic into the ones you pick. [Enola](INSTALL.md#enola) is an optional tool that
maps code architecture.

`PLASTIC_CHANNEL` picks the beta or alpha channel:

```bash
curl -fsSL https://raw.githubusercontent.com/zalom/plastic/main/install.sh | PLASTIC_CHANNEL=alpha sh
```

### A clean Mac

A clean Mac needs nothing more. `install.sh` brings the Ruby Plastic runs on, so Plastic never
uses the Ruby 2.6 that macOS ships.

### Check the installation

```bash
plastic version     # The version and the release channel
plastic doctor      # The installation, the databases and the hooks of this agent
```

`plastic version` prints the version, the release channel and the file the version came from.
It changes nothing and checks nothing else.

`plastic doctor` checks the releases, the launcher on your `PATH`, the Ruby version, the sqlite3
bundle, where the hooks point and the installer lock. It also opens each database and reads the hooks and instruction files of the
agent it runs in. It prints one row for each check, then the repair for each finding, and exits
1 when it finds a problem.

### Move from npm

To move an npm installation to the shell launcher, run `install.sh` once. It points the hooks
at the new launcher and keeps your stores and settings. See
[INSTALL.md](INSTALL.md#move-from-npm) for the details.

[INSTALL.md](INSTALL.md) covers update, rollback, uninstall and the supported platforms.

## Quick start

```bash
# 1. Install for your agent
curl -fsSL https://raw.githubusercontent.com/zalom/plastic/main/install.sh | sh
plastic init                # Pick the agents to install into

# 2. See what is open
plastic status

# 3. Start an intent
plastic intent new "Add a --version flag"

# 4. Ask what to do next, at any time
plastic next
```

Restart your agent after the install. For the full path, read
[your first intent in 10 minutes](docs/guides/your-first-intent-in-10-minutes.md).

## How it works

An intent moves through the phases below: the go-ahead, the nodes, the judge, the close and the abandon.

![How an intent is delivered: What, Why, go-ahead and How, then judge, review by pull request and close. Abandon is open at any time.](docs/contributing/figures/delivery-phases.svg)

```
  You or your agent              plastic                     ~/.plastic/stores/SLUG/store
  -----------------              -------                     ----------------------------
  plastic intent new "..."  -->  creates the intent     -->  12--slug/intent.md
  plastic intent rule 12    -->  records a ruling       -->  Insights in 12--slug/intent.md
  plastic next              -->  names the next step    -->  graph.json, printed from the node rows
  plastic intent end 12     -->  closes the intent      -->  outcome.md, INDEX.md

        ^                                                              |
        |            next: one command       because: one reason       |
        +--------------------------------------------------------------+
```

Plastic follows four rules:

1. **Commands print state and rules.** The judgment stays with you and the agent.
2. **The ledger is append-only.** `savepoint.md` holds one line for each event, so a new
   session resumes from the last line.
3. **Status is derived.** Plastic reads what is ready from the graph and the ledger.
4. **Nothing leaves the machine.** Plastic makes no model call and sends none of your files anywhere.

## Commands

### Orientation
```bash
plastic status                        # Active work in every store
plastic graph resume                  # Where this project's work stopped and what runs next
plastic graph resume --stores blog,shop  # The same, for several named projects
plastic next                          # The next action in one line
plastic next --why                    # The next action, with the reasoning
```

### Intents
```bash
plastic intent new "LINE"             # Create an intent
plastic intent new "LINE" --parent 12 # Create a branch of intent 12
plastic intent show 12                # Print the state screen
plastic intent spec 12                # State screen, then the speccing rules
plastic intent rule 12 "TEXT"         # Record a ruling in Insights
plastic intent revise 12 "LINE" --why "TEXT"  # Rewrite the What and the Why, keeping the old text
plastic intent note 12 "TEXT"                     # Add a line under Notes in outcome.md; --kind Review, Commit or Report
plastic session note "TEXT"           # Append a savepoint note
plastic intent brief 12               # Print the brief an agent starts from
plastic intent link 12 cites 7        # Link intent 12 to intent 7
plastic intent unlink 12 cites 7 --dry-run   # Preview the removal of a link
plastic intent archive 12 --dry-run   # Preview an archive
plastic intent unarchive 12             # Restore an archived intent
plastic intent end 12                   # Close as delivered, after the merge
plastic intent abandon 12               # Close as abandoned
```

### Graphs and roadmaps
```bash
plastic graph show 12                 # The work graph of intent 12
plastic graph show 12 --dry-run       # The same call in a disposable copy
plastic graph ready 12                # The nodes ready to start
plastic graph check 12                # Find cycles and dangling ids
plastic node done 12 n3 "TEXT"   # Close a node
plastic node resolve 12 n3 "TEXT"                       # Resolve a node that needs info or is impeded
plastic node remove 12 n3 --dry-run   # Preview a node removal
plastic edge remove 12 n2 n3 --dry-run   # Preview an edge removal
plastic roadmap next                  # The roadmap most worth continuing
plastic roadmap show SLUG             # The state screen of one roadmap
plastic roadmap check SLUG            # Find cycles and dangling ids in the graph
plastic roadmap drop SLUG ITEM --dry-run        # Preview a dropped item
plastic roadmap edge remove SLUG FROM TO --dry-run   # Preview an edge removal
plastic roadmap log SLUG EVENT "TEXT" # Append a line to the roadmap ledger
```

A `--dry-run` call runs in a disposable copy of the store. It prints what it would
write, never touches the original, and ends with the same call without `--dry-run`.

### Auto teams
```bash
plastic auto 12                        # Take the delivery lock and print the code worktree
plastic auto my-roadmap                # Deliver the next item of a roadmap
plastic intent lock status 12          # Show who holds the lock
plastic intent brief 12 --role executor # Print the spawn preamble for one role
```

### Search
```bash
plastic search recovery flow --source-project blog --limit 20  # Ranked passages
plastic document get REFERENCE --json                           # One immutable document
plastic document batch REFERENCE... --json                      # Documents in request order
plastic intent discover 12 recovery flow                         # Save candidate provenance
plastic intent context 12 --from selected-context.json           # Save agent-selected context
plastic architecture status --project blog                       # Tell the agent to check the architecture map
plastic architecture refresh --project blog                      # Tell the agent to regenerate the map
```

### Stores and databases
```bash
plastic sync up                       # Bring the databases level with the store files; an intent folder with no rows gets its rows back
plastic project list                  # The registered projects with their paths
plastic project new blog ~/code/blog  # Register a project and leave its store ready for intent new
plastic project links                 # List the links that name an intent or a ruling this store lacks
plastic sync up --dry-run             # Show what would change
plastic sync down                     # Write the store files from the databases
plastic backup --store alpha          # Copy the databases of one store (or --store global) into a UTC-named folder
plastic backup --store alpha --live   # The same, printing each line of backup.log as it is written
plastic backup list --store alpha     # Folder, start time, status and goal of each backup
plastic backup purge --store alpha --older-than 2026-09-01   # Delete older backups
plastic backup purge --store alpha --failed   # Delete the backups that failed
plastic backup restore --store alpha --latest   # Put the newest done backup back; it ends with the sync down line
```

### Product
```bash
plastic init                          # Install into the agents you pick
plastic install --reinstall           # Copy the files again and sync every agent
plastic update                        # Next version on the current channel
plastic update --channel alpha        # Move to the alpha channel
plastic rollback                      # Switch back to the previous release
plastic rollback --version 2.0.0-alpha.27
plastic uninstall                     # Remove Plastic from the agents you pick. Your stores stay.
plastic version                       # The installed version and its channel
plastic doctor                        # The installation, the databases and the hooks of this agent
```

### Help
```bash
plastic help                          # All commands and help topics
plastic help intent end               # The usage line of one command
plastic help roadmaps                 # One help topic
```

## Global options

```bash
--json          # Print the result as data with stable keys
-h, --help      # Print the usage line of the command
--project SLUG  # Name a project other than the one the working directory is in
```

The installer commands and `plastic hook EVENT` do not take `--json`.

## Examples

**Active work in every store:**
```
$ plastic status
global    0 active
blog      1 active  14
shop      2 active  7, 9

next: plastic graph resume --stores shop
because: the working directory is inside shop
```

**The next action:**
```
$ plastic next
next work  9  in Batch 2: checkout flow

next: plastic intent show 9 --project shop
because: 9 is the first active intent in shop
```

**The installed version:**
```
$ plastic version
version:         2.0.5
channel:         latest
source:          ~/.local/share/plastic/active/VERSION

next: plastic status
because: the command line works, so read the work next
```

The slugs and ids in these examples are samples.

## Agent hooks

The installer registers hooks in your agent. At session start a hook loads the conventions
and prints where the work stands, and another checks GitHub for a newer release at most once every 12 hours.
When a session stops or ends, a hook records it. Each hook
calls the active release launcher under `~/.local/share/plastic`:

```bash
plastic hook start      # SessionStart; the agent calls these, not you
plastic hook stop       # Stop
plastic hook end        # SessionEnd
```

The start hook names the harness that runs the session and records it on the session row.
The other hooks and commands read it from there.

Run `plastic doctor` when hooks do not fire. Use `--harness codex` or
`--harness claude-code` to choose the installation to check. Codex runs a hook only after
you trust it in `/hooks`, and the installer names each hook that changed. The doctor names
each repair, such as `plastic install --reinstall`.

## Supported AI tools

| Tool | Install | State |
|------|---------|-------|
| **Claude Code** | `plastic init` | Supported |
| **Codex CLI** | `plastic init` | Supported |
| **Hermes** | none | A packaging target only |

The `plastic` command itself needs no agent. It runs in any shell with Ruby. See
[harness support](docs/reference/harness-adapters.md) for the detail on each agent.

Four agents ship with Plastic: a planner that drafts or reviews a plan, an executor that
builds it, and two advisors for hard decisions. Your main session dispatches each one for one
step and records what it reports.

## Configuration

`~/.plastic/config.yml` holds the settings you changed, in a `global` section and one
section per harness:

```yaml
global:
  runner:
    stop_hook: true                  # Keep working while a node is ready
harnesses:
  codex:
    agents:
      models:
        plastic-executor: gpt-5.5    # One agent's model under Codex
```

```bash
plastic config list                         # Every key with its value
plastic config set runner.stop_hook true    # Write a global key
plastic config get agents.models.plastic-executor --harness codex
```

See the [configuration guide](docs/guide/getting-started/configuration.md) for every key and file.

### Uninstall

```bash
plastic uninstall     # Remove what Plastic wrote into the agents you pick
```

The uninstall removes what the record of each agent lists, so your own settings stay. Your
stores under `~/.plastic` stay.

## Documentation

- **[INSTALL.md](INSTALL.md)**: every install path.
- **[docs/guide/](docs/guide/index.md)**: getting started with the `plastic` command.
- **[docs/guides/](docs/guides/index.md)**: task guides, from your first intent to picking a mode.
- **[docs/usage/](docs/usage/FEATURES.md)**: features, the audit guide and tracking.
- **[docs/internals.md](docs/internals.md)**: how Plastic stays deterministic.
- **[docs/contributing/](docs/contributing/ARCHITECTURE.md)**: the system architecture in drawings, the command architecture, the coding practices and the gates.
- **[CHANGELOG.md](CHANGELOG.md)**: one entry for each release.

## Privacy

Plastic runs on your machine. It makes no model call and sends none of your files anywhere.
Three things use the network: `install.sh`, the update check hook and `plastic update`. They read
the release list from GitHub and download a release from there. `install.sh` and `plastic update`
also download Ruby: from the jdx/ruby releases on GitHub, or from the Homebrew registry on an Intel
Mac. Bundler fetches the sqlite3 and tty-prompt gems
from RubyGems when a release installs. See [SECURITY.md](SECURITY.md) for every file the installer writes.

## Built with Plastic

Plastic is developed through Plastic. The roadmap, the intents, the plans, the decisions and
the outcomes behind each release are part of the record.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT. See [LICENSE](LICENSE).
