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
- **How**: the work is planned (`plan.md` plus `checklist.md` plus at least one real `actions/ACTION_N.md`).
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
Claude Code and Codex. Its Ruby fixtures execute an npm archive in disposable homes,
including harness registration and public project and intent creation. These deterministic
checks supplement the live authenticated agent runs; they do not claim full doctor or
all-command acceptance.

### intent directory contents

Every intent is a folder named `ID--slug/` inside a store's `store/` folder. Lifecycle artifacts (spec, plan, checklist, outcome) always live in this intent directory in the store, never in the project repository.

```
ID--slug/
  ID--slug.md     # the intent file (its base name equals the folder name)
  spec.md         # the Why deliverable
  plan.md         # the How deliverable (planning)
  checklist.md    # the How deliverable (execution registry)
  outcome.md      # the Exec deliverable (a disposition: delivered|abandoned header at close)
  savepoint.md    # deterministic cycle-step ledger, written automatically
  graph.md        # the node graph `plastic intent step` runs (Goal, Decisions, Graph, Status)
  nodes/          # one file per graph node
  delivery.lock   # the delivery lock, present while a session owns the delivery
  revisions.md    # optional structural-maintenance audit trail (present only after maintenance)
  actions/        # action files
  resources/      # research, references, snapshots, diagrams
```

`plastic intent new` runs `scripts/new-intent`, which creates the intent file, `actions/`, `resources/`, the born `What` line in `savepoint.md`, and placeholder copies of `spec.md`, `plan.md`, `checklist.md`, and `outcome.md`. Each placeholder starts with `<!-- plastic:placeholder -->`, so a file that still carries that line is not a real artifact. The other files appear when the command that uses them first runs. At close, `plastic intent end` backfills `spec.md`, `plan.md`, `actions/ACTION_1.md`, and `outcome.md` from the record wherever a file is missing or still a placeholder.

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
unclosed prior day (backfilled `spec.md`, `plan.md`, `actions/ACTION_1.md`, `outcome.md` from the
ledger, open items carried into today, a `closed:` stamp), three days per boot at most.
`promote-session-item` turns one ledger line into a registered intent. See `docs/internals.md`,
"the session close path and the next-day sweep".

### Plastic runs no version control command

Plastic never runs `git`, `gh`, or `glab` on a project's behalf (intent 390). `plastic session commit "SUMMARY"` records a verified checklist item as one `Item` savepoint line (through `SessionLedger`, with `--ref` carried into the line when given) and prints the instruction that lands it: inside a registered project, change to its path and commit the way that project's own `AGENTS.md` says, plus one line per pull request or merge request template `PullRequestTemplates.detect` finds in the repository, or a pointer at `plastic help completion-and-done` when it finds none; outside a registered project, the record still lands (in the global store by default) and the instruction names no repository. `plastic auto start ID` is the same shape for the code worktree: it arms the delivery lock and prints the expected worktree path and branch, and the agent that receives the instruction runs the `git worktree add` itself. See [internals](internals.md#plastic-runs-no-version-control-command) for the mechanics.

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
add`); it moves through `open`, `claimed`, `done`, `failed` and `parked`, or leaves the graph
as `removed` (`Graph::Node::MOVES` is the one source of which moves are legal). An edge
(`plastic edge add`) says one node needs another; a guarded SQL insert refuses a self edge, an
edge touching a missing or removed node, and an edge that would close a loop.
After the cause of a failed edge addition or removal is fixed, the same command can retry.

`Graph::NodeWriter` and `Graph::EdgeWriter` own these writes. Every state move is a guarded
`UPDATE ... WHERE state IN (...)`, so two attempts to move the same node cannot both win; the
one that finds no row back re-reads the node to report why. Claiming a node caps at three
retries: the fourth claim parks the node with a standing question instead of claiming it, so a
node that keeps failing surfaces to the owner rather than looping. The full command set:
`node add`, `node remove`, `node claim`, `node release`, `node done`, `node fail`, `node park`,
`node answer`, `edge add`, `edge remove`.

## rulings, the spec and arming delivery

`knowledge_graph.db` also holds `rulings` and `links`. `plastic intent rule ID TEXT` writes
the owner's next decision as the next `D` id in that intent; `--supersedes RULING_ID` links it
to the ruling it replaces, which stays on record rather than being overwritten.
`Graph::RulingWriter` owns the write; `Graph::Spec` reads an intent's `spec.md` document row
for its done criteria and open decisions, the bullets under a `Done criteria` or `Open
Questions` heading (a section holding only "None" counts zero).

`plastic intent spec ID` prints `docs/grilling.md`, the grilling method, then the intent's
open decisions, so the next step is always either `intent rule` or `auto start`.
`plastic auto start ID` refuses (exit 3) an open decision, no done criterion, a done or
abandoned intent, and a live lock held by another session; it fails (exit 1) when the call
names no session. Otherwise it takes the lock in `auto` mode, sets the intent active, and
reprints its files. An already active intent still needs a live auto lock held by the
calling session; starting it takes a missing or expired lock.

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

`plastic backup` packs `home.db`, each store's three databases, and the home's `origin_id`,
`config.yml`, and `projects.yml` when present into one gzipped archive under `backups/`.
The identity file lets an unpacked backup read the rows under their original owner.
`plastic backup list` flags an archive that is missing or that changed
since it was written.

`plastic sync up` imports a selected legacy store completely: intents, rulings, source
and chain links, roadmaps, and preserved original bytes. It then handles ordinary hand
edits through the same command. Use `--project SLUG` to select each store. The separate
migration command has been removed.

`plastic sync up --dry-run` runs the same operation in a disposable copy. It refuses a
source tree containing symbolic links so a preview cannot write through one into the
original tree. Plain sync retains its conflict checks and explicit merge or overwrite
options. Content files such as `Gemfile.lock` are kept; the old `delivery.lock` and
`.DS_Store` machine files remain excluded from ordinary sync. Archive snapshots include
those files too.

First import retains the source checkout by default. The existing
`migrate.remove_after_import` configuration remains supported for that first import only:
after success, it removes `INDEX.md` and archives done or abandoned intents. Ordinary
later sync does not repeat cleanup. Explicit archive reversal uses
`plastic intent archive ID --revert`.

Backups recover the same installation, including its origin identity. They are not a
colleague handover format. Team transport is deferred, and Plastic stores are not shared
through Git.

## Delivery acceptance

A graph with all nodes done advances to `intent end`. Closure also requires recorded
criteria, resolved decisions, a substantive outcome, and an explicit judge's evidence
for every criterion. The evidence and outcome hash remain in a completion row. Plastic
records this acceptance; the harness or owner performs the verification. Successful
closure releases the delivery lock and ends with no next command.

An empty graph hands planning to the harness. Claimed work stays with its worker,
parked work needs the owner's answer, and failed work advances to release before retry.
These handoffs use the agent workflow DSL and stop until the harness records its action.

Node completion requires nonempty findings. `node done --repair` records missing
verification for a done node after the work is checked again. `graph.json` always flows
from database rows to the checkout; sync never imports its node or edge content.
