# Features

This page describes how the `plastic` command behaves. `plastic help` lists every command, and
`plastic help COMMAND` prints one command's usage.

## One command, direct results

`plastic` prints a result and stops. It asks no question and makes no model call. A result is
rows of label and value, followed by two lines:

```text
next: plastic status
because: it needs no argument and names the rest
```

The `next:` line names the command to run now. The `because:` line gives the rule that chose
it. These two lines carry the order of steps.

## The same result as data

Add `--json` to any command except `install`, `update`, `rollback`, `uninstall` and `hook`.
The command prints its rows as a JSON document. The keys are stable, so a script can read them.

## Scope

A command works on one store. A project named with `--project SLUG` wins. With no name, the
project whose repository holds the current directory wins, and an inner repository beats an
outer one. With neither, the global store answers.

## Session commands

| Command | Result |
| ------- | ------ |
| `plastic status` | The work of every store, by group. |
| `plastic graph resume [--stores a,b]` | Where each named project's work stopped, and what runs next. |
| `plastic graph lapsed [--stores a,b]` | Each intent in agent delivery whose driver claim or node claim lapsed, with the node, the agent, the session and the last renewal, and the command that restarts the first. It renews no claim. |
| `plastic next` | The next action in one line, with the rule behind it on the `because:` line. |
| `plastic project list` | The registered projects with their paths, and `(no store)` for one whose store folder is missing. |
| `plastic project load [SLUG...]` | A short digest of each named project, or of the call's own store: its store and repository paths, the `AGENTS.md` and `README.md` to read, the intents in progress with the best passages of the retrieval graph for each (at most 3 intents and 2 passages each, on `context:` lines), the count of open intents, the last 3 deliveries and, for a project with a repository, an architecture line that leaves to the agent whether the repository holds code. A `then:` line says what to check, start and keep, and no `next:` line follows, because the next work waits for the owner. A new session in a project is told to run it first. |
| `plastic project new SLUG PATH` | Registers a project in `projects.yml`, keeping every other line, and leaves its store ready for `plastic intent new`. |
| `plastic project links` | Lists each link whose local end names an intent or a ruling the store lacks, and prints the count. |

`continue` and `next` read the same frontier: the ready intents. An intent is ready when every intent
it needs, by a `needs` link, is done or abandoned. `plastic intent link ID needs OTHER` writes the
link. With no ready intent, both name the first active intent instead.

## Auto mode

| Command | Result |
| ------- | ------ |
| `plastic intent start ID` | Sets a future, open or parked intent in progress for guided work, and prints its code worktree and branch. The agent makes the worktree at the printed path on the printed branch. A done or abandoned intent fails and offers `plastic next`, and an archived one fails and offers `plastic intent unarchive ID`. The calling session becomes the driver of the intent. Another session's live driver claim, renewed within 15 minutes and not ended with its session, refuses the call with exit 3 and names that session; `--take-over REASON` takes the claim on the owner's word and writes the old and the new driver to the work log. |
| `plastic intent auto ID` | The same start, for agent delivery: the agents settle the What, Why and How, and run `plastic intent approve ID` themselves when the `because:` line of `plastic intent spec` names it. It takes the driver claim and `--take-over REASON` as `plastic intent start` does. |
| `plastic intent park ID REASON` | Parks an intent in progress with the reason it waits. `plastic intent start ID` resumes it and keeps the reason. |
| `plastic intent grant ID REASON --owner` | Grants one extra review round, on the owner's word, to an intent whose review rounds are used and not accepted. It writes one `granted` work log line with the reason; each line adds one round, and a call while a round is left is refused. Without `--owner` it exits 2 and writes nothing. |

`plastic intent new` writes a future intent.
`plastic intent start` and `plastic intent auto` run no version control command: they print the
worktree, and the agent makes it. They end on `plastic intent spec ID` while the spec is unsettled or
the go-ahead that `plastic intent approve ID` writes is missing, and on `plastic intent brief ID`
otherwise. `plastic intent spec` offers `plastic intent brief ID` once the go-ahead exists. Before it,
the spec offers no command: in guided work the owner gives the go-ahead, and in auto the agents record it. A node claim, taken with `plastic node claim ID NODE --agent NAME`, names the session that works a node and the agent that runs it; a claim without `--agent` exits 2. It
refuses, with exit 3, an intent that is not in progress or without the go-ahead, and a node that
is blocked, held or capped; it offers `plastic next` for a done or abandoned intent. A claim whose
`--agent` differs from the environment variable `PLASTIC_AGENT` fails with exit 1, and each command
renews only the claims of the agent `PLASTIC_AGENT` names.

## Drive a graph from any harness

`plastic graph ready ID --json` lists the ready nodes as fields, and `plastic node claim ID NODE --json`
returns `result.packet`: the node, its criterion, its input paths, the stored output of each node it needs, the
rulings in force, the spec's constraints, what the lists left out, and the path of its schema file. `plastic node done ID NODE TEXT --output PATH` stores a file of JSON as
the node's output and refuses a file that is not JSON. `plastic graph check` finds a schema file that
names no live node and prints a `hand edit:` line for each finding no command repairs. A node added with
`--deadline MINUTES` that stays claimed longer than that is listed by `plastic graph ready` on an `overdue:`
line and under `result.overdue`, for the driver to check on its worker; Plastic moves no node for it. [Drive a graph from any harness](drive-from-any-harness.md) shows the loop.

## Rulings and revisions

| Command | Result |
| ------- | ------ |
| `plastic intent rule ID "TEXT"` | The next owner ruling, numbered in order (D1, D2 and on). `--supersedes RULING_ID` links it to the ruling it replaces. |
| `plastic intent revise ID "LINE"` | The intent's new What, and its new Why with `--why "TEXT"`. `--dry-run` prints the change and writes nothing. |
| `plastic intent note ID "TEXT"` | One line under `## Notes` in the intent's outcome.md, as `- Report: TEXT`. `--kind Review`, `Commit` or `Report` (the default) names the line. |

`intent revise` writes the new What and Why into the intent file, and its work log line keeps
the old What and Why. A done or abandoned intent refuses with
exit 3.

## Preview a change with --dry-run

Eight commands take `--dry-run`. It runs the whole call in a disposable copy of the store
and its home files, prints each file the call would add, change or remove, and ends with
`preview complete; the original store was not changed`. The `next:` line is the same call
without `--dry-run`. A store that holds a link to a folder is refused, because the copy
could not hold it safely.

| Command | What the preview shows |
| ------- | ---------------------- |
| `plastic edge remove ID FROM TO --dry-run` | The work graph rows the removed edge would change. |
| `plastic node remove ID NODE --dry-run` | The node and edge rows the removal would delete. |
| `plastic intent unlink ID KIND TARGET --dry-run` | The links the removal would delete. |
| `plastic intent archive (ID \| --older-than DATE) --dry-run` | The files the archive would remove, and the rows it keeps. |
| `plastic intent unarchive ID [--dry-run]` | The archived directory restored exactly as archived. |

`plastic store sync up`, `plastic store sync down`, `plastic intent revise` and `plastic store backup` keep their own previews. `plastic store backup --live` prints each line of the backup's `backup.log` as it is written. `plastic store backup purge` (with `--older-than`, `--all` or `--failed`) and `plastic store backup restore` take `--dry-run` and list what they would delete or put back. A restore ends with a line that tells the agent to ask the person whether to run `plastic store sync down` or `plastic store sync up`, and it offers no command.
`plastic uninstall --dry-run` lists every path the uninstall would remove or change.

## Install into a harness

| Command | Result |
| ------- | ------ |
| `plastic init` | Lists the harnesses found on this machine, every one picked, and installs Plastic into each one the person picks. |
| `plastic install` | Copies the core files into the home and makes the global store. `--reinstall` copies them again and syncs every harness Plastic is installed into. |
| `plastic uninstall` | Lists the harnesses Plastic is installed into, picked, and removes from each picked one exactly what its record lists. |

A harness counts as found when its settings folder is in the home or its program is on the
`PATH`. Both lists use the [choice screen](../help/choice-screen.md): from inside an agent the
call prints the numbered list and stops, and the agent runs `plastic init ANSWER` or
`plastic uninstall ANSWER` with the person's answer. Plastic writes only into a harness the
harness registry holds. Each install writes a record under `~/.plastic/installations/`, one
file for each harness, that lists the files, hooks, settings entries and instruction sections
it wrote. The uninstall reads that record, so the person's own settings entries stay. Only the
main session runs Plastic's hooks. After an install into Codex, open `/hooks` in Codex and
trust the changed hooks.

## Installer commands

`plastic install`, `plastic update`, `plastic rollback` and `plastic uninstall` run the
installer scripts as child processes. A script that exits 3 makes the command exit 3, and any
other failure exits 1. See [INSTALL.md](../../INSTALL.md).

## Settings

`plastic config list` prints every setting with its value, `plastic config get KEY` prints one,
and `plastic config set KEY VALUE` writes one into the settings rows of `~/.plastic/plastic.db` and prints `~/.plastic/config.yml` from them. The one-time import of an older `config.yml` resolves YAML anchors and merge keys to plain values, and the printed file holds none. A `config.yml` edited by hand after the print is refused: move it aside, then run `plastic config set KEY VALUE` to print it again. `plastic config` shows
the on/off settings on a choice screen. Each takes `--harness NAME` to work on the settings of one
harness, and refuses a name the harness registry does not hold. See the
[page of `config`](../reference/commands/config/README.md).

`~/.plastic/config.yml` is printed from the settings rows. It shows the settings you changed, in a
`global` section and one section per harness, and holds no anchors:

```yaml
global:
  runner:
    stop_hook: true                  # Keep working while a node is ready
  backup:
    daily: true                      # Keep 24 hours of backups, with two copies a day
harnesses:
  codex:
    agents:
      models:
        plastic-executor: gpt-5.5    # One agent's model under Codex
```

A sync always reads the Markdown notes and the graph of each intent. Under `resources/`, it reads
`output/reports` and `output/files` by file type, Markdown and HTML unless `sync.types` names others,
in `output/reports` only a report recorded with `plastic intent report ID PATH` or one that
`reports.mandatory` names, the `references` folder when `sync.references` is on, and never `tmp`. A
file of a type not yet named is skipped once, with one line that gives the `plastic config set
sync.types` command to include it. `plastic init` offers images and videos picked. Tool output,
packets, plans and notes go to `resources/tmp`, and copies of outside material go to
`resources/references`.

With `backup.daily` on, each store keeps 24 hours of backups instead of three days. The first
Plastic command or hook of the day copies the databases of every store as the start-of-day backup,
and each session end after it replaces the day's end-of-day backup. A store always keeps its
newest backup, and `plastic store backup list` and `plastic store backup restore` take no daily backup, so they
find the backups as they are. Plastic runs no background process for this, and `backup.daily` is
off by default.

`migrate.drop_document_revisions` holds back the migration that drops the `document_revisions`
table of each store. While it is off, `plastic update` leaves that table in place. Turn it on with
`plastic config set migrate.drop_document_revisions true`, then run `plastic update`: each store
loses the table, and a later migration deletes the copy the drop kept, since the table was a mistake.
The switch is off by default.

## Chat history

`plastic hook prompt` records each prompt you type in the `chat_messages` table of
`~/.plastic/plastic.db`, with the session, the harness, the store and the intent in play. A call
with no store records the prompt with an empty store and intent. Set `chat_sync` to `full` with
`plastic config set chat_sync full` to record the reply at the end of each turn as well; the
default, `user_only`, records prompts alone.

`plastic chat list` prints the recorded messages of every store in time order, one row each with
the time, the store, the intent and the text. `--since YYYY-MM-DD` leaves out older messages; the
day starts at midnight in the zone of the clock. A message whose store folder is gone is still
listed, and one line names the store. The command only reads: the text prints to the terminal and
nothing is written. See the [page of `chat list`](../reference/commands/chat-list/README.md).

## Read the databases in a console

`plastic console` opens IRB in Plastic's own process over the databases of one store, chosen with
`--project NAME`, and the machine-wide `plastic.db`. Each file is opened read-only under the name
of its file: `work`, `knowledge`, `retrieval` and `plastic`. A write through any of them fails
with `attempt to write a readonly database`. The console is no sandbox: Ruby can still write
files. `plastic console --eval CODE`, short `-e`, runs one piece of Ruby for an agent, prints its
value and exits 0. Code that raises prints the error and exits 1. With `--json` the value prints
as JSON data, and `--json` without `--eval` exits 2. The console renews no claim and takes no
daily backup, so a call writes nothing in a store. IRB is the one of the Ruby
installation, not of the install: when the Ruby has none, the console says so and exits 1
(`gem install irb` adds it), and every other command works, `--eval` included. See the
[page of `console`](../reference/commands/console/README.md).

## Check the installation

| Command | Result |
| ------- | ------ |
| `plastic version` | Also `plastic --version`. The version, the release channel and the file the version came from. |
| `plastic doctor` | One row for each check of this harness, then one repair row. Exits 0 when every check passes and 1 on a finding. |

`plastic doctor` checks the version record, Ruby, the sqlite3 gem, the machine database, each
registered project's store and its three databases, PLASTIC.md, and each project's AGENTS.md.
In Claude Code it also checks the Claude version record, the hooks in
`~/.claude/settings.json`, the import line in `~/.claude/CLAUDE.md`, and each project's
CLAUDE.md. In Codex it checks the record in `~/.agents/plastic/VERSION`, the
hook commands and executable launchers in `~/.codex/hooks.json`, and the PLASTIC.md
line in `~/.codex/AGENTS.md`. It reports a custom `CODEX_HOME` that differs from the
installer location. Hook trust prints an unverified reminder to review `/hooks`;
that reminder does not change the exit code. A row reads `ok` or names the finding.
The repair row lists each repair once: a
command, or a line to add to a file. The doctor reads files and opens the databases read-only,
except for one repair: it rebuilds the search rows of a store that are out of step with the
passages, and prints `search index NAME: rebuilt`. A store whose evidence is gone fails with
the `plastic store backup list --project NAME` repair. The start hook never rebuilds. `--harness NAME` checks a named harness instead of the one the session row
records. When nothing names a harness, the doctor exits 2 and lists the registered harnesses.

The doctor also gives one `layout NAME ID--SLUG:` row for each intent folder that breaks the layout,
and says what is wrong there: the files outside the layout, the retired files and an old
`revisions.md`. The retired entries of the store folder, such as `.sessions/`, get one
`layout NAME store/:` row. Each of these rows names the repair `plastic intent repair --all --project
NAME`, and the `next:` line names it too. An entry of the store folder that holds data is left to a
person: its repair says to move it out of the store folder by hand. A `revisions.md` that the repair
cannot read gets the same kind of repair by hand.

## Undo a migration

A migration that removes the owner's data keeps it in `legacy.db` in the store folder, in the same
transaction. A migration that removes what an agent made by mistake deletes it and keeps no copy and offers no undo. The ledger in `plastic.db` records each migration that runs on a
store. The migration that drops `document_revisions`, and the one that trims what it kept in
`legacy.db`, run only once `migrate.drop_document_revisions` is on; the switch is off by
default.

| Command | What it does |
| ------- | ------------ |
| `plastic store migration list --project SLUG` | Prints the newest version the store records, the rows its `legacy.db` holds, its ledger rows and what a down would undo now. The store answers for itself, and the ledger rows are its history. It changes nothing and offers no next command. |
| `plastic store migration down --project SLUG` | Backs the store up and puts back the rows the newest migration kept, in their old shape, then offers `plastic store migration list --project SLUG`. |
| `plastic store migration purge VERSION --project SLUG` | Takes a backup of the store when the newest is older than 12 hours, as other commands that can lose data do. Then it removes the rows one migration kept and gives their space back to the disk. After it, a down cannot undo that migration. |

A down exits 3 and changes nothing when the store is not at the newest version, when the newest
migration the store records kept nothing or its rows were purged, or when a row it would put back changed after
the migration. `plastic update` migrates the store up again after a down.

## The resources layout

An intent folder keeps its notes in the root and its other files under `resources/`:
`resources/output/reports/` for the recorded reports and the reports the config makes
mandatory, `resources/output/files/` for every other output, `resources/references/` for copies
of outside material, and `resources/tmp/` for tool output, packets, plans, notes and other state
that no sync keeps. A sync reads the output folders by file type: Markdown and HTML by default, and
more types through the setting `sync.types`. In `resources/output/reports/` it reads only a
report that `plastic intent report ID PATH` recorded or that the setting `reports.mandatory`
names; every other file there stays on disk with no row. Which work needs a report is the
guidance of `plastic help completion-and-done`; the command records. Each recorded report gets
one line under `## Reports` in outcome.md. When a sync up no longer reads a path, it removes the rows of that
path. `resources/references/` is read only when its
setting is on, and `resources/tmp/` never. When a sync finds a type it does not read, it says
so in one line and records the type once in `sync.asked`.

`plastic intent repair ID` applies this layout to the folder of one intent, and `plastic intent
repair --all` applies it to every intent folder of the store and to the store folder. It renames
a file that has an older name, and moves each other file to the folder the layout names. It moves
the rows with the files, rewrites the relative links that point at a moved file, and runs a sync
up. A link that named no file before the move is left as it is. A loose Markdown or HTML file moves
to `resources/tmp/`, and a file directly under `resources/output/` of another type moves to
`files/`. A file in `resources/output/reports/` that is neither recorded nor mandatory is named and
moved to `resources/tmp/`. A file that a recorded or mandatory report of any intent links to stays
where it is. The repair removes the retired files that the layout names, such as an old lock. It turns each
entry of an old `revisions.md` into an `amended` line with the date of the entry, then removes the
file. With `--all`, it also removes the retired entries of the store folder, such as `.sessions/`
and `.tmp/`, and names each entry that holds data and leaves it.

A done or abandoned intent changes in its structure only, never in its work. Its folder gets one
`amended` line on the intent's work log that lists every rename, move and removal, each kind with
its reason. The files of an old `actions/` folder move as one change, and an empty `.gitkeep`
placeholder is removed, not moved. Each link the repair rewrites gets an `amended` line of its own,
whose row keeps the exact old and new link in the fields `old_text` and `new_text`. An intent that
a driver claim or a live node claim holds is refused with exit 3, and `--all` repairs the other
intents first. Both the run and `--dry-run` print one line for each intent folder, the links that
change and the other `amended` lines, then the totals: the intent folders and their changes by
kind, counted apart, the links that change, the `amended` lines and the links left as they are.
The links left as they are print only as a count unless `--links-left` lists each one. `--dry-run`
writes nothing. A target that
holds other bytes than the file that would move onto it stops the call with exit 3 and names the
target. A second run finds nothing to change and says `repaired: nothing to change`.

## Help that costs nothing

`plastic help` reads one table and loads no command file. It prints the core commands first,
then one heading for each family: intent, project, sync, session, config, backup, migration,
document, architecture, node, edge, graph, chat and hook. `plastic help FAMILY` lists one family, and
`plastic help --json` prints a list of families, each with its commands. `plastic <command> --help` prints
the usage line without building the command. An unknown command prints the closest name.

## Exit codes

| Code | Meaning |
| ---- | ------- |
| 0 | Succeeded |
| 1 | Failed |
| 2 | Called wrongly |
| 3 | Refused, because the step belongs to the owner |

## Starts without Node

`exe/plastic` is a Ruby script. It uses the Ruby standard library only and loads with
RubyGems off. `install.sh` installs it from a GitHub release. In an installed release,
`bin/plastic` is a shell launcher that starts the release's own Ruby by its full path, so the
Ruby on your `PATH` does not matter.
