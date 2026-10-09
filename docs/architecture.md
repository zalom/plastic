# architecture

## overview

The development gate starts coverage before timing instrumentation and checks
the exit status of each rerun. Timing reruns select one test file or acceptance
document. Mutation reruns resolve only ids with explicit verdict evidence;
aggregate kill counts cannot establish an individual verdict.

Plastic is an intent store plus a thin tooling layer over it. The store is plain files (folders, Markdown, YAML frontmatter) that capture desires and carry them through a fixed lifecycle; the tooling (the `plastic` command, hooks, scripts, agents, templates) keeps the store well-shaped and automates the deterministic parts. This document describes the system structure. For how the cycles actually execute (operational mechanics, harness detail), see [internals](internals.md). For the pitch and quick start, see the [README](../README.md).

## the two processes

Plastic runs two processes at once. They are nested, not alternatives: the lifecycle of a single intent runs inside the never-ending loop of the whole system.

### coordinator loop (build, observe, repeat)

The outer heartbeat is **Build, Observe, Repeat (B to O to R)**, driven by the coordinator across the whole system:

- **Build**: advance whatever intent is currently active.
- **Observe**: read what the work surfaced.
- **Repeat**: pick the next thing.

It never ends while the store is in use.

### intent lifecycle (what, why, how, exec)

The inner, finite life of a single intent is **What to Why to How to Exec**:

- **What**: the desire is captured (the intent file with `## Intent` filled).
- **Why**: the desire is justified and decided (`## Context` plus `spec.md`).
- **How**: the work is planned as a work graph: nodes, each tied to a done-criterion key of `spec.md`, and the edges between them. `graph.json` is the checklist.
- **Exec**: the work is carried out and the result recorded (`outcome.md` plus the `## Outcome` summary).

Once Exec completes, the intent is done.

### how they connect

Each intent keeps an append-only work log in the `## Insights` section of its intent file. Append-only means newest entry at the bottom, never prepended, so the trace reads in order across every intent. Those insights are exactly what the coordinator reads in its Observe phase to decide what to Build next. The inner lifecycle feeds the outer loop through Insights.

## the store layout

A store is a folder of intents. There are two scopes, structurally identical, differing only in location and purpose.

- **Global store**: one per person, holding strategic intents (personal goals, research, framework work). Person-level configuration sits in the Plastic home, `~/.plastic/`: a preferences file (`config.yml`) and a project registry (`projects.yml`).
- **Project stores**: one per project, holding tactical intents (concrete work items inside that project). A project store root adds one settings file, `project.yml`, copied from `templates/project.yml`.

Each store root has exactly one `INDEX.md` and a `store/` folder holding one directory per intent. A store root can also hold a `roadmaps/` folder. A fresh install creates the stores layout, where every store root sits under `~/.plastic/stores/` and the global store is the root named `global`:

```
~/.plastic/
  config.yml
  projects.yml
  stores/
    global/
      INDEX.md
      roadmaps/
      store/
        ID--slug/
    {slug}/
      INDEX.md
      project.yml
      roadmaps/
      store/
        ID--slug/
```

So the global store is `~/.plastic/stores/global/store/`, and a project store is `~/.plastic/stores/{slug}/store/`.

Homes created before the stores layout use the legacy layout. There the global store root is `~/.plastic/` itself (`~/.plastic/INDEX.md` and `~/.plastic/store/`), and project store roots sit at `~/.plastic/projects/{slug}/`. Plastic reads the stores layout when `~/.plastic/stores/` exists, and reads the legacy layout when it does not. The installer bootstraps the legacy layout only when the home already holds a legacy `store`, `projects`, `INDEX.md` or `roadmaps` entry. That layout mover belonged to the earlier command line. The current kernel expects stores under `stores/`; `sync up` imports their legacy content. Reinstalling does not move user data.

The rule of thumb: if the work changes a specific project's code it is tactical and belongs in that project's store; otherwise it is strategic and belongs in the global store. When in doubt, global. Stores are personal and local; the Plastic home is git-tracked locally but never pushed to a remote.

`varar/store-layout.md` checks fresh installation and legacy migration separately for
Claude Code and Codex. Its Ruby fixtures execute a release archive in disposable homes,
including harness registration and public project and intent creation. These deterministic
checks supplement the live authenticated agent runs; they do not claim full doctor or
all-command acceptance.

### intent directory contents

Every intent is a folder named `ID--slug/` inside a store's `store/` folder. Lifecycle artifacts (spec, outcome, the work graph print) always live in this intent directory in the store, never in the project repository.

```
ID--slug/
  intent.md       # the intent file (an imported folder keeps ID--slug.md)
  spec.md         # the Why deliverable
  graph.json      # the checklist, printed from rows: go-ahead, verdicts, nodes with criterion keys, edges
  context.json    # saved discovery and context, printed from rows when a row exists
  outcome.md      # the Exec deliverable (a disposition: delivered|abandoned header at close)
  savepoint.md    # deterministic cycle-step ledger, written automatically
  graph.md        # the node graph `plastic intent step` runs (Goal, Decisions, Graph, Status)
  nodes/          # one file per graph node
  revisions.md    # optional structural-maintenance audit trail (present only after maintenance)
  actions/        # action files
  resources/      # research, references, snapshots, diagrams
```

`plastic intent new` runs `scripts/new-intent`, which creates the intent file `intent.md`, `actions/`, `resources/`, the born `What` line in `savepoint.md`, and placeholder copies of `spec.md` and `outcome.md`. Each placeholder starts with `<!-- plastic:placeholder -->`, so a file that still carries that line is not a real artifact. The other files appear when the command that uses them first runs. At close, `plastic intent end` backfills `spec.md`, `actions/ACTION_1.md`, and `outcome.md` from the record wherever a file is missing or still a placeholder.

Lifecycle artifacts use those exact reserved names and live directly in the intent folder, never in subfolders and never renamed. All other supporting material goes in `resources/`. State is not stored in a status field. The INDEX.md terminal sections are the canonical done marker (see "intent done and the end tail" below), and the stage is derived from which artifacts carry real content. `revisions.md` is not a lifecycle artifact: it appears only when structural maintenance relocated a misplaced section, file, or ref out of a delivered intent, so its existence signals structural (not conceptual) change.

### the session day ledger

Inside the global store folder sit two dot-prefixed paths (intent 297): `.sessions/`, one shared day ledger per calendar date, and `.tmp/`, a per-session scratch area. Both are invisible to every store walker precisely because of the leading dot, so neither one is, or ever becomes, an intent. In the stores layout the global store folder is `~/.plastic/stores/global/store/`; in the legacy layout it is `~/.plastic/store/`:

```
~/.plastic/stores/global/store/
  ID--slug/
  .sessions/
    YYYYMMDD/
  .tmp/
    <session-id>/
```

A day directory's members appear in order as the day is used, not all at once:

```
.sessions/YYYYMMDD/
  YYYYMMDD.md    # the only file at scaffold time
  checklist.md   # on the first append, header written under the lock
  savepoint.md   # on the first append, no header
```

The day id is the local wall-clock date, digits only with no hyphen, so it satisfies every id pattern in the store with no special case. One day directory is shared by every session that touches that day, project agnostic, with each checklist and savepoint line tagged by session and project. A day ledger has no `INDEX.md` entry. `SessionLedger` (`scripts/lib/session_ledger.rb`) performs every write to `checklist.md` and `savepoint.md` inside a day directory. `scripts/append-ledger` is its command-line front, and the hooks call the library directly.

### the session close path and the next-day sweep

At `SessionEnd` the `close` hook drops the session's never-acted-on pending lines, removes its
`.tmp/<session-id>/` scratch, and, if the session crossed midnight, files yesterday in the
background. The real backstop is the first boot of a new day: `hook-session-start` files every
unclosed prior day (backfilled `spec.md`, `actions/ACTION_1.md`, `outcome.md` from the
ledger, open items carried into today, a `closed:` stamp), three days per boot at most.
`promote-session-item` turns one ledger line into a registered intent. See `docs/internals.md`,
"the session close path and the next-day sweep".

### Plastic runs no version control command

Plastic never runs `git`, `gh`, or `glab` on a project's behalf (intent 390). `plastic session commit "SUMMARY"` records a verified checklist item as one `Item` savepoint line (through `SessionLedger`, with `--ref` carried into the line when given) and prints the instruction that lands it: inside a registered project, change to its path and commit the way that project's own `AGENTS.md` says, plus one line per pull request or merge request template `PullRequestTemplates.detect` finds in the repository, or a pointer at `plastic help completion-and-done` when it finds none; outside a registered project, the record still lands (in the global store by default) and the instruction names no repository. `plastic auto ID` is the same shape for the code worktree: it takes the delivery lock and prints the expected worktree path and branch, and the agent that receives the instruction runs the `git worktree add` itself. See [internals](internals.md#plastic-runs-no-version-control-command) for the mechanics.

## identity and the knowledge graph

Intents are addressed by Folgezettel IDs, following Luhmann's alternating convention. Assigning an ID requires only reading the existing IDs in the store:

- **Root intents** are sequential integers: `1`, `2`, `3`. The next root is one greater than the highest existing integer root.
- **Branches alternate number and letter** as they descend from the parent: `1` to `1a` to `1a1` to `1a1a`.
- **Sibling branches increment the final segment**: the first child of `14` is `14a`, then `14b`, then `14c`.

Whether to branch is a meaning decision: branch when the new intent cannot stand on its own without its parent; make it a root when it is independent, even if inspired by another intent (record the provenance in `sources`).

Intents form a double-linked graph, recorded in two mirrored places:

- **Frontmatter** (the machine-followable graph): `sources` are backward links (what influenced this intent) and `chain` are forward links (what this intent spawned). If `B` lists `A` in its `sources`, then `A` should list `B` in its `chain`.
- **Prose** (the human-readable graph): wikilinks under `## Links`, written `[[ID]]` or `[[ID|display text]]`. A tactical intent links back to its governing strategic intent with `[[global:ID]]`.

The frontmatter graph drifts over time as it is edited by hand, so two pieces of machinery keep it honest. `scripts/rebuild-graph` is a deterministic, idempotent maintenance tool that repairs the `sources`/`chain` graph across every store `StoreDiscovery` finds, in one pass: it dedupes each array, enforces the I-invariants one-directionally (a formative edge wins over a duplicate; missing in-store backlinks are added; relational forward links survive), and resolves cross-store refs against a multi-hop relocation map built from every store's `## Relocated` log, so a relocated target is repointed (and collapsed to a bare id when it now lives in the referring store) and a coincidentally-reused id never wins over a recorded relocation. Every change is written to a per-store before/after audit, and a re-run over a repaired store is a no-op. Complementing it, `doctor.rb` carries a `graph_cross_store_resolution` check that resolves every cross-store ref against the full store family (not just shape-checks it), so a well-formed ref pointing at a relocated or deleted intent is caught rather than silently accepted. See [internals](internals.md) for the module split and the named id-reuse hazard.

Each store's `INDEX.md` is a structure note, not a table of contents: it groups intents by meaning and records where each one sits in the person's attention (`## Active`, `## Future`, `## Clusters`, `## Abandoned`, `## Completed`). It does not record lifecycle stage, since that is derived from the files.

## the work graph

Each store's `work_graph.db` holds one intent's nodes and the edges between them, alongside
its `intents`, `clusters` and `savepoints` tables. A node is one unit of work (`plastic node
add`); it moves through `open`, `claimed`, `done`, `failed`, `needs_info` and `impeded`, or leaves the graph
as `removed` (`Graph::Work::Node::Writer::MOVES` is the one source of which moves are legal). An edge
(`plastic edge add`) says one node needs another; a guarded SQL insert refuses a self edge, an
edge touching a missing or removed node, and an edge that would close a loop.
After the cause of a failed edge addition or removal is fixed, the same command can retry.

`Graph::Work::Node::Writer` and `Graph::Work::Edge::Writer` own these writes. Every state move is a guarded
`UPDATE ... WHERE state IN (...)`, so two attempts to move the same node cannot both win; the
one that finds no row back re-reads the node to report why. Claiming a node caps at three
retries: the fourth claim moves the node to needs_info with a standing question instead of claiming it, so a
node that keeps failing surfaces to the owner rather than looping. The full command set:
`node add`, `node remove`, `node claim`, `node release`, `node done`, `node fail`, `node ask`,
`node impede`, `node resolve`, `edge add`, `edge remove`.

### The planning directive

Every plan and planned change follows the Principle of Least Surprise: a name does what it says, a word means the same thing everywhere, nothing has hidden side effects, standard conventions come first. The work graph handles every ambiguity, newly found issue and blocker. An ambiguity gets at least 3 research attempts, then `plastic node ask ID NODE TEXT` naming the question and what was tried. An impediment stops the node at once with `plastic node impede ID NODE TEXT`. `plastic node resolve ID NODE TEXT` reopens either. A new issue becomes `plastic node add` plus `plastic edge add`. `plastic node fail ID NODE TEXT` is for work tried and failed.

Plastic prints this text in the planning hand-off and in every claimed-node instruction (`Graph::Work::PlanningDirective::TEXT`). `node done` and `node fail` take the findings or the reason as one positional TEXT and no options.

## rulings, the spec and arming delivery

`knowledge_graph.db` also holds `rulings` and `links`. `plastic intent rule ID TEXT` writes
the owner's next decision as the next `D` id in that intent; `--supersedes RULING_ID` links it
to the ruling it replaces, which stays on record rather than being overwritten.
`plastic intent revise ID LINE [--why TEXT]` rewrites the What and the Why after grilling:
`Graph::Knowledge::Intent::Reviser` writes the intent file as a new document revision, with the
new line under `## Intent` and the new lead under `## Context`, then the title in the intents
row. The old revision row stays, and the call prints its qualified reference. A done or
abandoned intent refuses with exit 3, and the call prints no file: `plastic sync down` does.
`Graph::Knowledge::Ruling::Writer` owns the write; `Graph::Knowledge::Spec` reads an intent's `spec.md` document row
for its done criteria and open decisions, the bullets under a `Done criteria` or `Open
Questions` heading (a section holding only "None" counts zero).

`plastic intent spec ID` prints `docs/grilling.md`, the grilling method, then the intent's
open decisions, so the next step is always either `intent rule` or `auto`.
`plastic auto ID` refuses (exit 3) an open decision, no done criterion, a done or
abandoned intent, and a live lock held by another session; it fails (exit 1) when the call
names no session. Otherwise it takes the lock in `auto` mode, sets the intent active, and
prints the code worktree. An already active intent still needs a live lock in auto mode held
by the calling session; running the command takes a missing or expired lock.

## roadmaps, links, archive and backup

A sync preview reports what it would import and offers `plastic sync up`.
Dropping a missing roadmap item fails before any write and names the missing roadmap or item.

A roadmap is a plan of several intents, kept as rows in `work_graph.db`. It holds batches.
Each batch has a goal and done criteria, and each item in a batch can wait on other items.
`plastic roadmap batch` and `plastic roadmap add` write the plan. `plastic roadmap start`
opens a ready item's intent and copies the item's goal and done criteria into that intent's
spec. An item's state is never stored. It is derived on each read from its intent's status
and from the items it waits on: done, dropped, in flight, blocked or ready. `plastic roadmap
next` prints the first ready item, or what is in the way. `plastic roadmap show` prints the
plan and reprints `roadmaps/<slug>.md` from the rows.

`plastic intent link` writes a typed link from one intent to another. A link to a live intent
stops that intent from being archived.

`plastic intent archive ID` saves the entire directory in `work_graph.db` before
removing it. The snapshot includes hand edits, binary files, dotfiles, lock files,
empty directories, symlink targets, file modes and modification times. Open intents
and intents linked from live work are refused. Special files are refused before
removal. Archived intents stay out of `sync down`.

`plastic intent archive ID --revert` restores the snapshot. It preserves conflicting
files and keeps the archived marker until the directory is restored. An interrupted
call can retry; a completed archive offers `status`, so following its next command
does not undo it. Restored hand edits that differ from live document rows need
explicit sync conflict resolution. A plain sync cannot silently overwrite them.

Roadmap writes reject an item that depends on itself. Reading an imported cycle reports
its unresolved items as blocked, and `roadmap check` identifies the loop.

`plastic backup --store SLUG` copies the three databases of one registered store, or of the
global store (`--store global`, the one name that is not a key of `projects.yml`), with
`VACUUM INTO`, into `stores/SLUG/backups/YYYYMMDDHHMMSS/`. The folder name is the UTC time,
with `-1`, `-2` added on a collision. `--databases LIST` copies only the named ones. A
`status.yml` in the folder holds `status:` (`in-progress`, `done` or `failed`) and `goal:`
(`full` or `partial:` and the file names). `backup.log` in the folder gets one line for each database (name, size in bytes, result)
and a last line that says the backup is done, or failed and why. Every line starts with a UTC
time and is on disk before the next copy starts. `plastic backup --live` prints each line
as it is written. A finished backup also gets one row in the
`backups` table of `local.db`, named `SLUG/TS`.
`plastic backup list --store SLUG` reads the folders and shows the number, the folder name,
the local start time, the status and the goal. It exits 1 for a backup whose row is
missing on disk or changed, and does not fail for a folder with no row.
`plastic backup purge --store SLUG (--older-than DATE | --all | --failed)` deletes folders
and rows before a UTC time, all of them, or the folders whose status is `failed`. `plastic backup restore --store SLUG (--timestamp TS | --latest)` puts
back a `done` backup after a safety backup of the current databases. It refuses while a
delivery lock is fresh. It never syncs by itself, because a sync can undo a restore. With a terminal it asks
whether to sync down, sync up or neither, gives one line for each answer, and runs the
chosen sync for the same store; an unknown answer is asked once more and then counts as
neither. With no terminal, and under `--json`, it asks nothing and its `next:` line tells the
agent to ask the person. `--dry-run` and a refused restore ask nothing. A terminal is an
input stream that answers `tty?`; `CLI::Dialog` decides it from `Environment#input`.

`plastic sync up` imports a selected legacy store completely: intents, rulings, source
and chain links, roadmaps, and preserved original bytes. It then handles ordinary hand
edits through the same command. Use `--project SLUG` to select each store. The separate
migration command has been removed.

`plastic sync up` reads every intent folder of a store, whatever `store/index.json` says. The folders are the true state on disk, and the index is a local convenience that the sync prints again from the rows after it reads. A folder with no intent row gives a row built from the front matter of its own intent file, with status `open`. A folder that cannot give a row, because it has no intent file, the file does not parse, or its number is shared with another folder, is named with its reason and none of its files are read. The other folders are read, and the call exits 1. A folder with no row cannot conflict, since no row exists to overwrite, so the rule that refuses a silent overwrite still applies only to a file whose rows also changed.

`plastic project list`, `plastic project new SLUG PATH` and `plastic project links` manage the projects of `projects.yml`. `project new` refuses a bad name (exit 2), `global` and a name registered at another path (exit 3), and a path that is not a folder (exit 1). It leaves the three store databases ready.

`plastic sync up --dry-run` runs the same operation in a disposable copy. It refuses a
source tree containing symbolic links so a preview cannot write through one into the
original tree. Plain sync retains its conflict checks and explicit merge or overwrite
options. Content files such as `Gemfile.lock` are kept; the retired `delivery.lock` file and
`.DS_Store` machine files remain excluded from ordinary sync. Archive snapshots include
those files too.

First import retains the source checkout by default. The existing
`migrate.remove_after_import` configuration remains supported for that first import only:
after success, it removes `INDEX.md` and archives done or abandoned intents. Ordinary
later sync does not repeat cleanup. Explicit archive reversal uses
`plastic intent archive ID --revert`.

Backups recover the databases of one store on the same installation. They are not a
colleague handover format. Team transport is deferred, and Plastic stores are not shared
through Git.

## Delivery acceptance

`plastic intent approve ID` writes the owner's go-ahead; `plastic auto ID` refuses (exit 3) an intent without it. A node is added with `--criterion KEY`, a done-criterion key of `spec.md`, and is done with `plastic node done ID NODE TEXT`, the text being its findings. `plastic intent judge ID` prints the steps that start a reasoning judge, and the judge records its verdict with `plastic intent verdict ID accept|revise TEXT`. A review has two rounds; a second `revise` is the owner's step (exit 3).

`plastic intent end ID` takes no options. It closes the intent when every live node is done, every criterion key is covered by a done node, the latest verdict is `accept` and is not older than the newest node change, and `outcome.md` is substantive with a `## Verification` section holding a `Merged:` and an `Architecture map:` bullet. With `review.pull_request: required` (the default) the section also holds a `Pull request:` bullet and, before the close, an `Approved:` bullet; a pull request without approval is a refusal (exit 3). With `off` neither bullet is asked for. The completion row holds `judge` `verdict` and the evidence built from rows: each criterion key with its done nodes and their findings. Closing releases the delivery lock, prints the intent's files and hands the agent the wind-down steps (`Workflows::WindDownIntent`): stop the processes and agents the intent started. Missing records the agent can write come back as a handoff; when the merge or map record is missing, `Workflows::CheckMerge` hands the agent both steps.

`plastic intent abandon ID` takes no options. It hands the agent the revert steps (`Workflows::RevertIntent`) until `outcome.md` holds a `Reverted:` bullet under `## Verification`, then closes the intent as abandoned with no completion row. The disposition is `superseded` when a `supersedes` link from another intent points at it, otherwise `cancelled`.
An intent needs at least one live node; small work needs no intent, because the session rows record it.

An empty graph hands planning to the harness. Claimed work stays with its worker,
work in needs_info waits for the owner's resolution, and failed work advances to release before retry.
These handoffs use the agent workflow DSL and stop until the harness records its action.

Node completion requires nonempty findings. `node done ID NODE TEXT` on a done node
replaces its findings after the work is checked again. `graph.json` always flows
from database rows to the checkout; sync never imports its node or edge content.

## component map

The tooling layer is thin and sits on top of the store. The parts that supply determinism do so by construction, never by judgement.

- **Skills**: no workflow skill ships in 2.0. Intents 304 and 372 retired the former `SKILL.md` packages into the `plastic` command and the `docs/help/*.md` chapters. The `skills/` directory still holds one shared fragment, `skills/_decision-tables.md`; the installer copies top-level `_`-prefixed Markdown fragments into `~/.plastic/` rather than into a skill directory. The general skill-authoring standard lives in the `skill-creating` and `skill-evaluating` skills at [zalom/agent-skills](https://github.com/zalom/agent-skills), and `docs/skill-authoring.md` keeps the Plastic-only rules.
- **Agents**: role files shipped in `agents/` that the installer syncs into each harness agent directory (Claude, Codex, Hermes) and tracks in that harness's manifest, so they prune on update and uninstall cleanly. Seven ship. In auto mode `plastic-enforcer` leads and reviews and `plastic-executor` builds, one team per intent. `plastic-node-work`, `plastic-node-research` and `plastic-node-verify` run the nodes the graph runner dispatches. `plastic-primary-advisor` and `plastic-secondary-advisor` are consultation agents. See `docs/help/agent-architecture.md` for the team model.
- **Installation**: `install.sh` brings the Ruby Plastic runs on. It pins one build for each platform by address, SHA-256 and size in its `ruby_pins` table: jdx/ruby for Apple silicon and Linux, and the Homebrew portable Ruby for an Intel Mac. Each Ruby lives in its own read-only directory, `~/.local/share/plastic/rubies/<key>`. `scripts/build-release` copies the pins into the release manifest, and `InstallerRelease::RubyChoice` (`scripts/lib/installer_release/rubies.rb`) reads them back on install and update. Each release gets a shell launcher, `releases/<version>/bin/plastic`, that starts its Ruby by its full path and runs the Ruby entry point at `libexec/plastic`, and a `bin/ruby` that starts the same Ruby for the `check-update` hook. An uninstall removes the Rubies last, since it runs on one of them.
- **Hooks**: lifecycle event handlers. The kernel writes three hook groups, defined in `Plastic::Hooks::Entries` (`scripts/lib/plastic/hooks/entries.rb`): SessionStart runs `plastic hook resume`, Stop runs `plastic hook record`, and SessionEnd runs `plastic hook record --end`. Each one calls the active release launcher, `~/.local/share/plastic/active/bin/plastic`, so an update or a rollback needs no hook rewrite. A copy installed from npm calls `~/.plastic/bin/plastic` instead, and `install.sh` rebinds those hooks to the active launcher. `HookRegistry` (`scripts/lib/hook_registry.rb`) adds `check-update` on SessionStart and keeps the names of retired hooks, which the installer purges from an old `settings.json` or `~/.codex/hooks.json`. Codex receives the same three kernel groups in `~/.codex/hooks.json`. The edit-path gates and the stage-transition gates were removed in 2.0 (intent 302): no hook gates a write on the lock or the stage.
- **Scripts**: small deterministic Ruby programs that encode mechanical rules, for example assigning the next Folgezettel ID from the existing IDs in a store. Most `plastic` commands run one of them. `plastic intent new` runs `scripts/new-intent`, which allocates the id, creates the directory tree, renders the born-complete intent file, writes the placeholder lifecycle files, wires the reciprocal links, and self-validates (intent 60b); the command then adds the intent's line to `## Active` in INDEX.md. `new-intent` touches neither git nor project creation. `plastic intent verify` runs `scripts/verify-intent`, which merges doctor, an added-line em-dash diff guard, a diffstat check, and an optional caller-supplied suite command into one verdict; Plastic runs no version control command (intent 390), so the em-dash guard scans diff text the caller supplies (`--diff-file`) instead of running `git diff` itself, printing the `git diff` command to run when none is supplied, and the diffstat check prints the `git diff --stat` command instead of running it. `plastic intent end` runs `scripts/end-intent`, and `plastic intent step` and `plastic intent answer` run `scripts/runner`. `plastic feedback` runs `scripts/feedback-report`, backed by `scripts/lib/feedback_report.rb` (intent 174): it redacts secrets, writes a local report file, and builds a prefilled GitHub issue URL, with no send path anywhere in the code. Deterministic by construction.
- **Templates**: the fixed FORM of each artifact (its sections, their order, frontmatter fields, file name). Two people following the same template produce artifacts of identical shape even when the words differ. Deterministic by construction.
- **Conventions**: `PLASTIC.md` (installed at `~/.plastic/PLASTIC.md`) is the always-on core. On Claude Code, the installer's managed block in `~/.claude/CLAUDE.md` imports it with an `@~/.plastic/PLASTIC.md` line; on Codex, the managed block in `~/.codex/AGENTS.md` points at it. A dedicated Minitest test (`test/plastic_core_budget_test.rb`) holds it under 200 lines, 1,600 estimated tokens and 8,192 bytes, and `bin/plastic-bench` measures it (intents 223 and 313). Deeper doctrine ships as the `docs/help/*.md` chapters, which `plastic help TOPIC` prints on demand. Intent 372 retired the 1.x conventions skill and its chapter load lines.

For the operational detail behind these parts (determinism coverage, harness taxonomy, upgrade backlog), see [internals](internals.md).

### per-agent models

Every shipped agent in `agents/*.md` pins an explicit model alias and effort in its frontmatter, never `inherit`. The installer passes that frontmatter through unless an `agents.models.<name>` config override names another model, in which case the override is honored as written. The shipped tiers are:

| Agent | Model |
|---|---|
| `plastic-enforcer`, `plastic-node-verify` | `opus` |
| `plastic-executor`, `plastic-node-work`, `plastic-node-research` | `sonnet` |
| `plastic-primary-advisor`, `plastic-secondary-advisor` | `fable` |

The enforcer dispatches a plan reviewer before code and a post-execution reviewer when a review rule fires; neither reviewer is a standing agent file. Primary Advisor and Secondary Advisor are not lifecycle roles, and the auto pipeline never dispatches either. Both use Fable on Claude Code and Astra on Codex; Primary uses medium effort, and Secondary uses high effort. Every other agent ships at medium effort.

A project or the global store can override any agent's tier through `agents.models.<basename>` config; see [internals](internals.md) for the config precedence and the installer mechanism that applies it. The graph runner's dispatch line also names the model it resolved for each node, so a dispatch does not depend on the harness reading frontmatter.

### the advisor: two consultation agents, never injected (intent 185)

Two consultation role files are tracked separately from lifecycle tiers by `AgentModels::CONSULTATION_AGENTS`, and neither is dispatched by the auto pipeline. On Claude Code, `plastic-primary-advisor` and `plastic-secondary-advisor` both ship with `model: fable`, at medium and high effort. On Codex, both use `gpt-6-astra`, at medium and high effort. Secondary Advisor carries the full Operating Manual in its body. Model overrides use the same harness-scoped `agents.models.<harness>.<name>` mechanism as every other agent.

The `plastic-agent-advisor` skill was the front door until intent 372 retired it; `plastic help advisor-protocol` now carries when consulting is worth the money, and the configured advisor agent is called directly. Lifecycle agents and Primary Advisor ship at medium effort. Secondary Advisor ships at high effort. `agents.efforts.<harness>.<name>` is the explicit override, with project config over global.

Config uses keys matching `InstallerCore::DEFAULT_AGENTS` exactly (`claude`, `codex`, never `claude_code`). `advisor.enabled: false` skips both advisor agents on every harness. `advisor.claude.default` names an agent, never a model. Install asks which advisor is the default: Primary Advisor at medium effort, or Secondary Advisor at high effort. An unset value resolves to Primary Advisor. Installer flags are `--no-advisor` and `--advisor VALUE`, where `VALUE` is an agent name or the `primary` or `secondary` shorthand. Retired agent values migrate on install and update.

`agents.models` is harness-scoped from this release: `agents.models.claude.*` and `agents.models.codex.*`, with the pre-existing flat form (`agents.models.<name>: value`, no harness nesting) still honored as the claude harness, and nested winning over flat for the same agent. `AgentModels.models_section(config, harness:)` implements this: for `harness: "claude"` it merges the flat scalar entries with the `claude` sub-hash (nested wins); for any other harness it reads ONLY that harness's own nested sub-hash, never the flat entries. This closes a real latent bug: previously the same override map fed both `install_agents`' Claude frontmatter rewrite and `generate_codex_agents`' TOML `model` line, so a literal Claude model id set under the flat form could leak straight into a Codex config. `install_codex` now calls `agent_model_overrides(harness: "codex")`, so a model named under `claude` is never emitted to `codex`; a regression test (`test_agent_model_overrides_never_leaks_a_claude_model_id_into_codex`) pins this. Stage-agent tier translation to Codex reasoning effort (`AgentModels::EFFORT_BY_ALIAS`) is unchanged by this scoping.

`InstallerCore#generate_codex_agents` renders every shipped role, including consultation agents. `advisor.enabled: false` still omits both advisor roles on every harness.

Codex per-role model identity (intent 186): Codex has no vendor alias layer, so `AgentModels::CODEX_MODEL_BY_ALIAS` centralizes every Codex model id in one place, paired with the existing `AgentModels::EFFORT_BY_ALIAS` tier. A generated Codex agent TOML for a tier alias carries both lines, model first:

| Tier | Codex model | Reasoning effort |
|---|---|---|
| `opus` roles | `gpt-5.6-sol` | `medium` |
| `sonnet` roles | `gpt-5.6-terra` | `medium` |
| `haiku` roles | `gpt-5.6-luna` | `medium` |

Model and effort are shipped defaults, independently overridable through `agents.models.codex.<name>` and `agents.efforts.codex.<name>`. A literal Codex model ID still receives medium effort unless effort is explicitly overridden. Primary and Secondary Advisor TOMLs both use `gpt-6-astra`, at medium and high effort respectively.

### Store retrieval and architecture prompts

`plastic search` reads literal indexed passages from selected SQLite stores. It returns immutable
qualified references, local rank data, and deterministic federated rank fusion. `document get`
and `document batch` fetch those references without changing source stores. `intent discover` and
`intent context` keep selected evidence and provenance with the intent that owns it.

`architecture status --project SLUG` and `architecture refresh --project SLUG` are prompts for
the agent. The first tells it to check the project's architecture map and the second tells it to
regenerate the map, with a mapping tool it chooses, such as Enola. Plastic runs no mapping tool
and stores no map. Plastic also prints the same kind of instruction when it hands planning to the agent
("fetch the map before you plan") and in `plastic intent end` ("fetch it once more and note the tool
and revision as the Architecture map: line under Verification in outcome.md"). It does not check the planning fetch; a delivered close refuses an outcome.md without the `Architecture map:` line, but does not check that the map is true.

### Store search: sqlite3, native, with companion tools alongside

`plastic search TERMS` is Plastic's own store search index, built on sqlite3 (an install-time
checked dependency, alongside git; see Conventions above), never optional and never delegated to
an outside process. No Plastic command starts, registers with, or reads from QMD or Serena.
Enola is not called either; all three tools remain
companion tools a person runs by hand beside Plastic, documented in
`plastic help tools` (`docs/help/tools.md`) and pointed to by one line in `PLASTIC.md`. Intent
391 (2.0) dissolved the three optional-tool paths this section used to describe: the per-store
QMD collection topology and its `scripts/lib/qmd_sync.rb` / `scripts/qmd-sync` CLI, the
session-start hook's QMD report-only line, and `scripts/lib/power_tools.rb`'s presence probes
(`PowerTools.qmd?`, `PowerTools.serena?`, `PowerTools.enola?`) that doctor's readiness checks used
to call for Serena and Enola. All of it is gone: no Plastic code path detects, registers with, or
reports on any of the three tools any more. A person who has QMD, Serena, or Enola installed sets
them up and queries them outside Plastic, on the stores or the repository, exactly as `plastic
help tools` describes.

### intent born-complete validation

A single validator library, `scripts/lib/intent_validator.rb`, defines whether an intent is born complete (every required frontmatter field present, and `sources` and `chain` well-formed arrays of id references (bare ids, or cross-store references like global:1a2)). It is the only definition of that contract. It is exposed as the `scripts/validate-intent` CLI (exit 0 when complete, non-zero with a report otherwise) and consulted by both the `plastic intent new` command (a self-verify step after the write) and doctor (the `frontmatter_fields` and `frontmatter_valid` conventions checks). Intents are created only through `plastic intent new` and never hand-authored, so completeness rests on machinery rather than on agent discipline.

### project store provisioning

Project store creation has a single source of truth: the `scripts/provision-project-store` verb, backed by `scripts/lib/store_provisioning.rb`. It is pure filesystem and idempotent. It makes the store directory `store/` under the project root (`~/.plastic/stores/{slug}/store` in the stores layout, `~/.plastic/projects/{slug}/store` in the legacy layout). Then it writes, only if missing, `.gitkeep` in the store directory, and `INDEX.md` (from `templates/index.md`) and `project.yml` (from `templates/project.yml`) in the project root. It requires the project to already be registered in `projects.yml` (an unregistered slug exits non-zero and creates nothing) and performs no qmd mutation, so any caller (including a doctor fix) stays deterministic. `plastic project new` calls it, then runs `validate-project`. `plastic doctor` reports a missing store for an already-registered project; the internal `provision-project-store {slug}` creates it. Doctor's additive `project_store_dir` check warns (fixable) when a registered project's store directory is missing, naming `provision-project-store {slug}` as the fix.

## session boot

Boot is owned by hooks, so it runs by construction on every session start, not as prose a skill follows (intent 36a):

1. **Core doctor**: `hook-session-start` runs `doctor.rb --core` in-process, reusing the `Doctor` class so there is one source of truth for core health. The core check is binary (pass or error, never warn): it compares every core file against the SHA256 recorded in the install manifests (`~/.plastic/manifest.json` for global scripts and PLASTIC.md; `~/.claude/plastic/manifest.json` for agent-side files), and also confirms hooks are registered, scripts are executable, and the installed version matches.
2. **Load context**: the hook does not inject `PLASTIC.md` (intent 341). The harness loads it through the installer's managed instruction block (see Conventions above). The hook reads the store INDEX.md and projects.yml, detects the current project by matching the working directory, and adds the project banner, deprecation and update notices, the first-boot sweep result, and the day summary. Deeper doctrine is printed on demand by `plastic help TOPIC`, not primed at boot.
3. **Boot banner and version**: the result of the core check drives a binary banner. It names the installed version and ends in `doctor --core run: success` on pass, or `doctor --core run: error` plus a pointer to doctor on error. The banner is emitted on both the `hookSpecificOutput.additionalContext` channel (model-facing) and the top-level `systemMessage` channel (visible in the user's terminal). One `BootBanner` renderer feeds both channels so they cannot drift (intent 54). The hook never blocks (always exits 0).
4. **Statusline**: the `plastic-statusline` command renders the statusline. It is not a hook event: the installer writes it as Claude Code's `statusLine` setting, and only when the install-time choice below selects Plastic's line.

Install-time statusline choice is separate from the render-time hook above: `InstallerCore#statusline_choice` decides, once per install, whether to write Plastic's statusline over an existing one. A fresh settings file with no statusline gets Plastic's line with no prompt. An existing non-Plastic line triggers a keep-or-switch prompt in an interactive session, honors `--statusline keep|plastic` to skip the prompt, defaults to keeping the user's line in a non-interactive session, and is never re-asked on `--reinstall` (a repair keeps whatever is already configured). `merge_claude_hooks` still backs up the prior line to `~/.plastic/.cache/original-statusline.json` regardless of the choice, so a later switch or an uninstall can restore it.

`plastic status` and `plastic graph resume` then orient the session. Neither runs the health check, loads core, or sets the statusline, since the hooks already did. `plastic graph resume [--stores a,b]` reads the rows of each named store, the call's own store when none is named, and writes nothing. For each store it prints the intent in play, its done nodes, its claimed, parked and failed nodes, its last five savepoint lines, and `then:`, the store's own next command. The intent in play is the one `plastic next` picks (`Graph::Work::NextPick`), and the next command comes from the same `Graph::Work::NextOffer` that `plastic next` reads, so the two never differ. With several open intents and no lock it says `in play: none alone` and lists them. A store whose rows hold no intent while its folder holds intent folders says so, and its `then:` is `plastic sync up`, which rebuilds the rows from the folders. When a person says "continue", the agent runs this command and works from its output.

Each roadmap carries a ledger (intent 134): a name-paired `roadmaps/<slug>.savepoint.md`, the machine counterpart to the human `## Log`, which follows its roadmap into `roadmaps/archived/` on close. `plastic roadmap log SLUG EVENT "TEXT"` appends to it (the events are created, dispatched, parked, merged, release, handoff, closed, added, reordered, wave and batch), and `RoadmapQueue` reads its last line as the roadmap's last-event time when it ranks roadmaps. The ledger is never a status source: `INDEX.md` stays the source of intent status.

## the delivery lock and the record hook

The delivery lock is one row of the `locks` table in the machine's `local.db` (`Graph::Lock`), keyed by the store and the intent, and names the session delivering the intent. `plastic auto ID` (`Workflows::StartAuto`) takes it; `plastic intent end` releases it. Given a roadmap slug, `plastic auto SLUG` (`Workflows::PickDelivery`) arms the roadmap's first item in flight that is neither parked nor held by another session, and offers `plastic roadmap start SLUG ITEM` for the first ready item when none is in flight (intent 413). A live lock held by another session is refused with exit 3, never taken over.

Plastic starts no agent process (intent 391). The runner prints a dispatch line for the live session on every harness. On Codex it adds the `codex exec` command for that node, and the session runs it.

Removed in 2.0 (intent 302): the edit-path gates (edit, bash, code, lock, links), the create gate, and the stage-transition gates. No hook blocks a write any more; the record hook is the only write-path hook, and doctor checks (intent 308) replace enforcement.

The record hook (`PostToolUse`, on Write, Edit, NotebookEdit, and the six Serena edit tools) derives the intent directory directly from the written file path (it walks up to the first ancestor that looks like `.../store/ID--slug`) and appends the savepoint line there directly from the path, so an unset session or a headless background run never skips the ledger. On Stop it also renews every lock row the session holds (`renew_locks`). For a project-file write it promotes the session's pending day-ledger line and stops there. It never commits: since 2026-09-24 a commit is an explicit `plastic session commit` by whoever verified the item, after the hook once committed half-edited files with the prompt as the message.

Session resolution feeds `plastic auto ID` and the spawn preamble; it has a fixed precedence (intent 52). Claude Code does not export a session id env var into the hook environment; it passes `session_id` on the hook stdin JSON, so the hooks parse it out of stdin. The resolver picks the first non-empty of: the stdin `session_id`, the `CLAUDE_CODE_SESSION_ID` environment variable (the headless/background id), and a derived `auto-<digest>` key. The derived key is deterministic, so a session-less take and a later session-less check resolve to the same session key. A null session is never written to a lock row.

## worktree isolation and the delivery lock

Removed in 2.0 (intent 302): the edit-path gates (edit, bash, code, lock, links), the create gate, and the stage-transition gates are gone with their code. The paragraphs and list items of this section that described them were removed with them; what remains is the `record` hook (savepoint line, lock heartbeat, day ledger) and the doctor checks that replace enforcement (intent 308).

An intent whose delivery touches code runs in its own git worktree, and an intent's delivery is single-owner: exactly one session develops it at a time. In auto mode the worktree is the lock: the code worktree is where the one delivery happens, and the lock row records which session owns it (intent 413). The row holds the session id, the mode, and the times the lock was taken and last renewed. The session id is the sole authorization identity. Liveness is a lease against the 1800-second TTL (`Graph::Lock#live?`): the record hook renews the row, a live foreign lock means back off, and an expired one is taken over by the next `plastic auto ID`. `plastic intent lock status ID` (`Workflows::ShowLock`) reads the row back: session, mode, taken and renewed times, live or expired, and the code worktree. The earlier `delivery.lock` file, the internal lock program and the old start and lock subcommands of `plastic auto` are retired.

Plastic computes the worktree path deterministically and cwd-independently, but it creates nothing (intent 390): `Workflows::Worktree` resolves the project repo from `projects.yml`, derives the path and branch a code worktree would have, and checks whether that path already exists on disk. `plastic auto ID` prints `worktree:` and `branch:`, and while the folder is missing its `next:` line is `git -C <repo> worktree add <path> -b <branch>`, which the agent runs itself. One worktree is expected per project intent, named `{id}--{slug}`: the code worktree at `<repo>/.claude/worktrees/{id}--{slug}` on branch `plastic/{id}--{slug}`, where all code edits happen. A second, store worktree used to exist; intent 178 retired it. The closer removes the code worktree by hand after committing and merging.

An intent whose store resolves no repository (a research or decision intent in the global store, or a project with no path) still gets the lock; `plastic auto ID` prints no worktree, and the next step is the brief.

The delivery lock arbitrates at the whole-intent grain only: two subagents sharing one session id both hold it. Since 2.0 (intent 302) nothing enforces the lock at write time; it is how a team keeps one delivery in one place.

### intent done and the end tail (intent 93)

Done is one law with three signals that must agree. The INDEX `## Completed` or `## Abandoned` section is the single canonical terminal marker (the store-wide ledger a fresh session reads first), so it wins on any conflict. `outcome.md` is the deliverable-exists signal, mandatory at every terminal (delivered and abandoned alike) and self-declaring through a `disposition: delivered|abandoned` frontmatter header. The savepoint `Done delivered|abandoned` line is the audit echo. When the three disagree, INDEX is authoritative and `doctor` (the `done_signals` check) reports the mismatch.

The audit echo can itself drift, so a pure, disk-only detector (`Savepoint.savepoint_phantom_lines`, intent 134; the ledger code lives in `scripts/lib/savepoint.rb` since intent 303) checks it: a savepoint line is a phantom when its file-landing milestone is absent or still a sentinel placeholder, its `(stage, milestone)` pair is a duplicate, or a state line's stage prerequisite is missing on disk. Doctor's `savepoint_truthful` check (in `done_signals`) reports phantoms as a warning, never a failure. For a live (INDEX Active) intent its fix hint names `Savepoint.rebuild_savepoint`; a terminal (Completed/Abandoned) intent is immutable, so a phantom there stays report-only.

The End tail runs in a fixed order: `outcome.md`, then the INDEX terminal move, then the savepoint `Done` line, then the commit, then disarm (clears the lock and, when a worktree was provisioned, prints the removal instruction; intent 390 - Plastic removes nothing itself). The design put a QMD reindex last, after disarm, so the index never references a released lock; `scripts/end-intent` does not run it in 2.0, and no public close path reindexes (a known gap). No hook freezes the intent directory after the lock is released: since intent 302 no hook gates a write on the lock or the stage, and doctor's `done_signals` checks report drift instead.

Since intent 188, `scripts/end-intent` performs disarm itself, as its own step 5 after the
outcome/INDEX/savepoint/commit steps commit: the script's exit code 0 now means both "the
intent is closed" and "its delivery lock is gone," rather than the second half being left to
a separate one-liner an agent had to remember to run. A pre-flight guard resolves the calling
session and refuses the whole run before anything is written when a live foreign session
holds the lock, and reclaims a stale foreign lock automatically (audited to savepoint.md).
Plastic runs no version control command (intent 390), so it can no longer verify the code
worktree is clean before disarming; `--discard-worktree-changes` is still accepted for
backward compatibility but changes nothing now that there is no check left to override.
`end-intent`'s own INDEX-move parser and `IndexEntry.active?` now share
one matcher that accepts a real em dash or a plain hyphen as the id/title separator on read,
while every write still emits the real em dash.

A delivered close never merges code, and never checks that the code is merged (intent 390):
Plastic runs no version control command, so it cannot verify a merge itself. `end-intent`
authors the record and prints the merge instruction (the `git -C <intent-worktree> merge
--no-ff --no-edit <node-branch>` shape `NodeWorktree.merge` computes) for the closer to run
by hand, before or after the close; the close no longer blocks on it. The retired exit code 9
names this: checking the code branch was merged used to require real git commands, which
Plastic no longer runs.

## status and the report roster

`plastic status` prints one row per store this machine holds: the store's slug, its count of active intents, and their ids (for example `global  2 active  7, 9`). It then names one store to continue: the store whose repository holds the working directory when that store has active work, else the store with the most active intents, else `plastic help` when no store has active work. `--json` returns the same rows as a `result` hash of slug to summary. It renders no board, table, prose summary or ranking.

The dashboard is gone (intent 392). In its place, the `capture` hook runs `scripts/report-screen state --all` against the working directory's store when a prompt is exactly `continue`: the project store when the working directory maps to one, else the global store. It adds the plain-text roster (`report-screen state --all STORE_ROOT`) to the model context, and the same roster painted with `--ansi` to the user's terminal.

Same store state gives the same output regardless of model. Roadmaps are the planning surface: `plastic next` and `plastic graph resume` read the next action from the work graph rows, and `report-screen state` stays a state view.

## CLI output and progression

The command layer owns project scope and next actions. The command table is `scripts/lib/cli/table.rb` (intent 363): one frozen hash maps each command name to its file, its class, and the line `plastic help` prints. Help topics are the `docs/help/*.md` files, printed by `plastic help TOPIC`. Every command parses `--json` and `--project SLUG` through the shared `Command` parser, except the installer verbs (`install`, `update`, `uninstall`, `rollback`), which accept only their own flags, and `plastic hook EVENT`, which hands the event straight to its launcher. Emitted commands retain the resolved project. Repository paths and store paths both resolve scope, including filesystem aliases.

JSON commands capture script stdout under `result.output` and emit one document.
Diagnostics remain on stderr. Direct intents use their specification, plan, and
checklist to select work. Graph execution first checks ownership and names the
public lock command when ownership is absent. Completed intents have no next
action. A Future index entry does not remove an explicit roadmap block.

Without a roadmap, both `next` and `continue` select the first active intent.
Graph steps accept repeated `--return NODE=PATH` arguments and a harness override,
so the public command can complete the runner's dispatch and absorption cycle.

### Safe package transitions

The executable resolves its own package root, even when an older updater passes
an inherited package path. Update clears that inherited path and verifies the
installed version before reporting success. Rollback prints the install command
for the target version and starts no package process.

Homes using `stores/` cannot switch to versions before `2.0.0-alpha.28`, which
introduced that layout. This refusal happens before installation or hook cleanup.
Legacy homes retain their existing rollback behavior.

`plastic project links` saves its audit under the current global store's
`resources/` directory. Its dry-run writes no files. `plastic doctor` checks the
harness it runs in, and `plastic doctor --harness NAME` checks a named one. Each
harness has its own module in `Plastic::Doctor::HARNESSES`: Claude Code and Codex.
Codex reuses the shared installation and database checks. Its module reads the
record under `.agents/plastic`, the hooks under `.codex`, and Codex AGENTS.md.
Hook trust remains unverified and prints a reminder without failing file checks.

### Closing checks

`plastic intent end` refuses an untouched scaffold. An untouched
scaffold has only placeholder lifecycle files, no action or graph, no savepoint
entries after the first What line, and its code worktree (when one is expected)
still resolves to the same path Plastic would provision, since Plastic runs no
version control command and cannot inspect it further than that. Close it
with `plastic intent abandon`, or do the work first. Legacy intents with missing lifecycle
files still close through the backfill.

`--dry-run` runs the same refusals as the real close and writes nothing. It
refuses an untouched scaffold and a hollow delivered report. A passing dry run
ends with `next: none`. Checking that the code was actually merged, and
checking the worktree for uncommitted changes, are both retired (intent 390):
each required a real git command Plastic no longer runs; the merge instruction
prints instead, unconditionally, for the closer to run themselves.

A real delivered close refuses an untouched scaffold before it writes anything.
The hollow-report refusal runs later, after outcome generation and the
backfill, so a close it refuses may already have written `outcome.md` or action
files. INDEX.md, the savepoint `Done` line, and the store commit stay untouched
in that case. `plastic intent end` reports each of these refusals as exit 1
with the reason.

### Project registration

`plastic project new` accepts a slug of lowercase letters, digits and hyphens
that starts with a letter or digit. `global` is reserved for the global store.
Any other slug exits 2 before anything is written. A directory already in
`projects.yml` under another slug is refused with exit 1, naming that slug.

### Session commits on delivery branches

`plastic session commit` never commits on an intent's delivery branch or
worktree. Its note now names the real delivery lock of that intent: held by
another session, held by this session, or not held at all. It no longer
reports an agent lock that does not exist. The `next:` line no longer implies
that a commit landed; the printed line above it says whether one did.

### Preview in a disposable copy

A command that declares `previews` takes `--dry-run`. `Graph::DisposableCopy` snapshots the
databases of one store with `VACUUM INTO`, copies its files and its home configuration into a
temporary home, and refuses a link to a folder. The routine runs its whole chain against that
copy, and `Routine::PreviewOutput` prints each line with a `preview:` prefix, names the
original path and never the copy, lists the files the call would add, change or remove, and
closes with `preview complete; the original store was not changed`. A chain that holds an
agent workflow cannot preview, because the agent's steps run outside the copy. The copy is
deleted when the call ends.


### Sync preview

`plastic sync` rebuilds `work_graph.db` and `references.db` on every run. When
either is missing, the plan names it under `build`. The preview and the sync
now report the same work, and "nothing to do" means nothing is missing.

### Rendering

`plastic render` leaves out a leading YAML frontmatter block. A later `---`
line is still a horizontal rule.

### Roadmap health and selection

A roadmap whose graph has a cycle cannot compute a frontier. It now ranks after
every healthy roadmap, so `plastic next` and `plastic roadmap next` pick a
healthy one first. It is still reported as an error when nothing else is left.

`plastic roadmap next` shows the tied roadmaps when several are equally live.
`plastic roadmap check` names a cycle and every graph id that no batch lists.
`plastic roadmap show` adds a warning row for either problem and points at
`plastic roadmap check`.

### Node dispatch and the finished graph

A dispatch line names the agent type for the node's kind. A research or verify
node has no worktree, and its dispatch line and input both say it is read-only.
When a step leaves every node in a finished state, `plastic intent step` names
`plastic intent verify ID` as the next command instead of another step.

## the tri-graph kernel (intent 394)

The tri-graph design moves Plastic's work into three graph databases. Its kernel is stage 1 of
that build, and it sits beside the live command line under `scripts/lib/plastic/`, with
`scripts/lib/plastic.rb` as its entry. A command in the kernel is a routine: it walks a chain
of code and agent workflows, and it ends as finished, handed off, failed or refused. A routine
that writes keeps its facts in a `routine_runs` row of `work_graph.db`, so the call after an
agent hand-off picks up where the first one stopped.

The kernel is not wired yet. `bin/plastic` still calls the live command line, and the kernel's
command table is empty. The installer ships the kernel files with the rest of the command
line. The life of a routine call, the four endings and the hook reply are drawn in
[the contributor architecture page](contributing/ARCHITECTURE.md).

## History: the 1.x skill design

This section describes Plastic 1.x. It is not current behavior.

- **Skills.** In 1.x the workflows were `SKILL.md` packages: direct-mode routing, intent creation, brainstorming, planning, executing, releasing, indexing, and a conventions router skill whose chapters each consuming skill loaded on demand. Intents 304 and 372 retired them into the `plastic` command and `docs/help/*.md`.
- **Direct mode.** A booted session rested in direct mode, and the `plastic-direct` skill routed each prompt on a time estimate. A change of about five minutes ran inline, a vague prompt was offered a thinking intent, and a larger change was offered a dedicated intent. Intent 372 retired the skill.
- **Stage agents.** Each lifecycle stage had its own agent: discovery for What, brainstorming and spec agents for Why, a planner for How, the executor for Exec, and a curator for Done. Intent 304 removed all of them except `plastic-executor`.
- **The dashboard skill.** A prose skill filled Markdown board templates from the `dashboard.rb --data` payload. It was retired with the other skills.
- **The continue router.** A continue skill chose among a project route, an intent route that read the intent's savepoint first, and a roadmap route. `plastic graph resume` replaced it.

## One schema file

Every table is declared once, in `scripts/lib/plastic/graph/db/schema.rb`. A table marked
`legacy: true` holds old data that nothing new reads; `legacy_intents_data` keeps the plan,
checklist and action files of each intent. `docs/internals.md` has the four steps to retire a
kind of data.
