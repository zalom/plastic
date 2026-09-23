<h1 align="center">
  <img src="https://raw.githubusercontent.com/zalom/plastic/main/assets/plastic-logo.svg"
    alt="Plastic" width="360">
</h1>

<p align="center">
  <strong>One command that turns an intent into a durable, linked record of decisions, plans, delivery and outcomes</strong>
</p>

<p align="center">
  <a href="https://www.npmjs.com/package/@zalom/plastic"><img src="https://img.shields.io/npm/v/@zalom/plastic" alt="npm version"></a>
  <a href="https://www.npmjs.com/package/@zalom/plastic"><img src="https://img.shields.io/npm/dm/@zalom/plastic" alt="npm downloads"></a>
  <a href="https://github.com/zalom/plastic/actions/workflows/test.yml"><img src="https://github.com/zalom/plastic/actions/workflows/test.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/zalom/plastic/releases"><img src="https://img.shields.io/github/v/release/zalom/plastic" alt="Release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/npm/l/@zalom/plastic" alt="License: MIT"></a>
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
| Keep the reasons | Records each ruling in the intent, then consolidates them into `spec.md` |
| Plan the work | Holds the plan as a graph of nodes, and names the next ready step |
| Resume tomorrow | Prints where a project stands and the next action in one line |
| Hand work to an agent team | Arms a delivery lock, briefs each role and reports the result |
| Close the work | Generates `outcome.md` from the record and moves the intent to Completed |
| Find an old decision | Searches every store, ranked, with one excerpt for each match |
| Run many projects | Keeps one store for each project, plus a global store, all in plain Markdown and Git |
| Steer a long delivery | Reads a roadmap as a graph and names the entry most worth continuing |
| Protect the record | Writes one archive of the three databases and the config |

Every result ends with a `next:` line and a `because:` line. The `--json` option prints the
same result as data with stable keys.

## How the record is built

Each intent is one directory. It carries the same small set of files at every stage.

| Stage | Question | File on disk |
|-------|----------|--------------|
| What | What is the intention? | `{id}--slug.md` |
| Why | What context, evidence and decisions shape it? | `spec.md` |
| How | What is the plan? | `plan.md`, `checklist.md`, `actions/` |
| Exec | What was delivered? | `outcome.md` |

The files are plain Markdown in a Git repository that you own. See
[the architecture](docs/architecture.md) for the full store layout.

## Installation

Plastic needs Ruby 4.0 or later. The npm path also needs Node.js 18 or later, because `npx`
fetches the package. After the install, the `plastic` command runs on Ruby alone.

### npm (recommended)

```bash
npx -y @zalom/plastic install --claude
```

Replace `--claude` with `--codex` for Codex CLI, or pass both flags.

The npm path puts the command at `~/.plastic/bin/plastic` and does not change your `PATH`.
Link the command into a directory that is on your `PATH`:

```bash
mkdir -p ~/.local/bin
ln -sf ~/.plastic/bin/plastic ~/.local/bin/plastic
```

### Alpha channel

Plastic 2.0 is on the alpha channel.

```bash
npx -y @zalom/plastic@alpha install --claude
```

### Quick install without npm

```bash
curl -fsSL https://raw.githubusercontent.com/zalom/plastic/main/install.sh | sh
plastic install --claude
```

`install.sh` takes the newest release on a channel that carries the archive. The default
channel is stable; `PLASTIC_CHANNEL` picks another:

```bash
curl -fsSL https://raw.githubusercontent.com/zalom/plastic/main/install.sh | PLASTIC_CHANNEL=alpha sh
```

No stable 2.0 release carries the archive yet, so the default channel still installs the 1.x
line. Use the alpha channel for the `plastic` command, or npm. To move an installed Plastic
to another channel later, run `plastic update --beta` or `plastic update --alpha`.

### A clean Mac

macOS ships Ruby 2.6, which is too old. Install a newer Ruby first:

```bash
curl https://mise.run | sh
mise use --global ruby@4.0
```

### Verify the installation

```bash
plastic version     # Prints the installed version and the file it came from
plastic doctor      # Checks the install and the stores
```

## Quick start

```bash
# 1. Install for your agent
npx -y @zalom/plastic@alpha install --claude    # Claude Code
npx -y @zalom/plastic@alpha install --codex     # Codex CLI
npx -y @zalom/plastic@alpha install --all       # Every supported agent

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

```
  You or your agent                 plastic                        ~/.plastic
  -----------------                 -------                        ----------
  plastic intent new "..."   -->    creates the intent      -->    store/12--slug/12--slug.md
  plastic intent rule 12     -->    records a ruling        -->    the intent file, then spec.md
  plastic intent step 12     -->    runs the next node      -->    graph.md, nodes/, savepoint.md
  plastic intent end 12      -->    generates the outcome   -->    outcome.md, INDEX.md

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
plastic continue                      # Where this project stands and what runs next
plastic continue --project blog       # The same, for a named project
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
plastic intent note 12 "TEXT"         # Append a savepoint note
plastic intent step 12                # Run the next ready step of the graph
plastic intent answer 12 --node n3 --decision "TEXT"   # Answer a node that needs a decision
plastic intent verify 12              # Run the merge-gate checks
plastic intent end 12 --delivered --summary "TEXT"     # Close as delivered
plastic intent end 12 --abandoned --summary "TEXT"     # Close as abandoned
```

### Projects
```bash
plastic project list                  # Every store this machine holds
plastic project new blog --path ~/code/blog   # Register and provision a project
plastic project links                 # Rebuild every Links section from frontmatter
```

### Roadmaps
```bash
plastic roadmap next                  # The roadmap most worth continuing
plastic roadmap show SLUG             # The state screen of one roadmap
plastic roadmap check SLUG            # Find cycles and dangling ids in the graph
plastic roadmap migrate SLUG          # Write the graph section from the batches
plastic roadmap log SLUG EVENT "TEXT" # Append a line to the roadmap ledger
```

### Auto teams
```bash
plastic auto take 12                  # Arm the delivery lock for this session
plastic auto brief 12 --role executor # Print the spawn preamble for one role
plastic auto report 12                # Completion report, then the review rules
plastic auto lock status 12           # Inspect the delivery lock
plastic auto lock fix 12              # Repair a broken lock
plastic auto lock release 12          # Release the lock
```

### Sessions
```bash
plastic session summary               # Open items and recent activity in the day ledger
plastic session commit "SUMMARY"      # Commit one verified checklist item
plastic session handoff               # Write this session's hand-off
```

### Search
```bash
plastic index                         # Rebuild the search index from every Markdown file
plastic search recovery flow          # Ranked matches, one excerpt each
plastic search recovery --project blog --limit 5
plastic search --ask "Why did we drop the queue?"   # Search with a whole question
plastic query "SELECT path FROM doc LIMIT 5"        # One read-only SQL statement
```

### Stores and databases
```bash
plastic sync                          # Bring the store files and the three databases level
plastic sync --dry-run                # Show what would change
plastic checkout                      # Restore missing store files from the databases
plastic backup                        # One archive of the three databases and the config
plastic backup --list                 # Name, size and date of each archive
plastic migrate stores --dry-run      # Preview the move of every store under stores/
plastic migrate stores                # Move them, behind a full copy of the home
plastic render FILE                   # Print one Markdown file as an HTML page
```

### Product
```bash
plastic install --claude              # Install into Claude Code
plastic install --reinstall --claude  # Repair an install
plastic update                        # Next version on the current channel
plastic update --alpha                # Move to the alpha channel
plastic rollback                      # List the versions this machine has run
plastic rollback --version 2.0.0-alpha.27
plastic uninstall --all               # Remove Plastic from every agent. Your stores stay.
plastic doctor                        # Check the install and the stores
plastic doctor --core                 # The fast check that runs at session start
plastic doctor --json                 # The full report as data
plastic version                       # The installed version
```

### Help and feedback
```bash
plastic help                          # All commands and help topics
plastic help intent end               # The usage line of one command
plastic help roadmaps                 # One help topic
plastic feedback "TITLE" < report.md  # Save a problem report and print a link that files it
```

## Global options

```bash
--json          # Print the result as data with stable keys
-h, --help      # Print the usage line of the command
--project SLUG  # On continue, next and search, name a project other than the current one
```

The installer commands do not take `--json`. `plastic doctor` does, and prints its full
report as the document.

## Examples

**Active work in every store:**
```
$ plastic status
global    0 active
blog      1 active  14
shop      2 active  7, 9

next: plastic continue --project shop
because: the working directory is inside shop
```

**The next action:**
```
$ plastic next
next work  9  in Batch 2: checkout flow

next: read ~/.plastic/projects/shop/store/9--checkout-flow/plan.md
because: 9 is first on the frontier of the roadmap
```

**The installed version:**
```
$ plastic version
version  2.0.0-alpha.28
source   ~/.local/share/plastic/package.json

next: plastic status
because: the command line works, so read the work next
```

The slugs and ids in these examples are samples.

## Agent hooks

The installer registers hooks in your agent. At session start a hook runs the fast doctor,
loads the conventions and prints the open items of the day. Each hook calls one launcher:

```bash
plastic hook EVENT      # The agent calls this, not you
```

Run `plastic install --reinstall --claude` when hooks do not fire.

## Supported AI tools

| Tool | Install | State |
|------|---------|-------|
| **Claude Code** | `plastic install --claude` | Supported |
| **Codex CLI** | `plastic install --codex` | Supported |
| **Hermes** | none | A packaging target only |

The `plastic` command itself needs no agent. It runs in any shell with Ruby. See
[harness support](docs/reference/harness-adapters.md) for the detail on each agent.

Seven agents ship with Plastic: an enforcer that leads an auto team, an executor, three node
agents for work, verification and research, and two advisors for hard decisions.

## Configuration

`~/.plastic/config.yml`:

```yaml
project_roots: ~/.plastic/projects   # Where Plastic looks for projects
stale_threshold_days: 3              # Age at which a future intent is shown for triage
context_offer_tokens: 150000         # Context size at which the agent offers to compact
context_insist_tokens: 250000        # Context size at which the agent insists
agent:
  type: claude-code                  # The agent that runs Plastic
  parallel_mode: agent-teams         # agent-teams or linear
```

Install-time choices:

```bash
plastic install --claude --advisor secondary   # Set the default advisor
plastic install --claude --no-advisor          # Install no advisor agent
plastic install --claude --statusline plastic  # Use the Plastic status line
```

See the [configuration guide](docs/guide/getting-started/configuration.md) for every key and file.

### Uninstall

```bash
plastic uninstall --all     # Remove hooks, agents and conventions from every agent
```

Your stores under `~/.plastic` stay.

## What changed in 2.0

Plastic 2.0 moves from prose skills to one command with direct results.

- **One `plastic` command.** More than 40 commands replace the skills. The package ships no skill directories.
- **Direct results.** Every command ends with `next:` and `because:`, and takes `--json`.
- **Plans are graphs.** An intent holds nodes and edges, and a ready set names what runs next.
- **A ledger with refusals.** Node transitions are appended to `savepoint.md`, and an invalid transition is refused.
- **Generated outcomes.** `outcome.md` is built from the graph, the nodes and the ledger at the close.
- **Roadmaps are graphs too.** `plastic roadmap check` finds cycles and dangling ids.
- **Search without a service.** One SQLite file holds a full-text index of every store.
- **Three databases.** `work_graph.db`, `knowledge_graph.db` and `references.db` hold the record, and the files are a checkout of it.
- **Backup and migrate.** One archive command, and a store move that runs behind a full copy of the home.
- **Two advisors, medium effort by default.** Summon the Primary Advisor or the Secondary Advisor on purpose.
- **Codex CLI as a second agent.** The same install, with OpenAI model ids for each role.
- **Publishing from branches.** A push to `alpha`, `beta` or `main` publishes to the matching npm channel with provenance.

The [changelog](CHANGELOG.md) holds one line for each release.

## Documentation

- **[INSTALL.md](INSTALL.md)**: every install path.
- **[docs/guide/](docs/guide/index.md)**: getting started with the `plastic` command.
- **[docs/guides/](docs/guides/index.md)**: task guides, from your first intent to picking a mode.
- **[docs/usage/](docs/usage/FEATURES.md)**: features, the audit guide and tracking.
- **[docs/architecture.md](docs/architecture.md)**: the structure, the store layout and the stage table.
- **[docs/internals.md](docs/internals.md)**: how Plastic stays deterministic.
- **[docs/contributing/](docs/contributing/ARCHITECTURE.md)**: the command architecture, the coding practices and the gates.

## Privacy

Plastic runs on your machine. It makes no model call and sends none of your files anywhere.
Two things use the network: the update check hook and `plastic update`, which ask the npm
registry for the newest version. See [SECURITY.md](SECURITY.md) for every file the installer writes.

## Built with Plastic

Plastic is developed through Plastic. The roadmap, the intents, the plans, the decisions and
the outcomes behind each release are part of the record.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT. See [LICENSE](LICENSE).
