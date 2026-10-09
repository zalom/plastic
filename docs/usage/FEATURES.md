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
it. The order of steps that the skills used to carry in prose lives in these two lines.

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
| `plastic status` | Active work in every store. |
| `plastic graph resume [--stores a,b]` | Where each named project's work stopped, and what runs next. |
| `plastic next` | The next action in one line. `--why` adds the rule behind it. |
| `plastic project list` | The registered projects with their paths, and `(no store)` for one whose store folder is missing. |
| `plastic project new SLUG PATH` | Registers a project in `projects.yml`, keeping every other line, and leaves its store ready for `plastic intent new`. |
| `plastic project links` | Lists each link whose local end names an intent or a ruling the store lacks, and fails with the count. |

`continue` and `next` read the same frontier: the liveliest roadmap, its open batch, and the
entries that are ready, in flight or blocked. With no roadmap, both name the first active
intent instead.

## Auto mode

| Command | Result |
| ------- | ------ |
| `plastic auto ID` | Takes the delivery lock of one intent for this session, sets it active, and prints its code worktree and branch. While the worktree folder is missing, the `next:` line is the `git worktree add` command that creates it. Given a roadmap slug, it arms the first item in flight, or names `plastic roadmap start SLUG ITEM` for the first ready item. |
| `plastic intent lock status ID` | The session that holds the intent's lock, its mode, when it was taken and renewed, whether it is live or expired, and the code worktree. |

`plastic auto` takes exactly one id and runs no version control command: it prints the
worktree command, and the agent runs it. A live lock of another session refuses with exit 3,
and an expired lock is taken over. `plastic auto ID` refuses an intent without the go-ahead
that `plastic intent approve ID` writes. `plastic intent end` and `plastic intent abandon` release the lock.

## Rulings and revisions

| Command | Result |
| ------- | ------ |
| `plastic intent rule ID "TEXT"` | The next owner ruling, numbered in order (D1, D2 and on). `--supersedes RULING_ID` links it to the ruling it replaces. |
| `plastic intent revise ID "LINE"` | The intent's new What, and its new Why with `--why "TEXT"`. `--dry-run` prints the change and writes nothing. |
| `plastic intent note ID "TEXT"` | One line under `## Notes` in the intent's outcome.md, as `- Report: TEXT`. `--kind Review`, `Commit` or `Report` (the default) names the line. The earlier text stays as a revision. |

`intent revise` writes the intent file as a new revision and keeps the old one, so the old
What and Why read back with `plastic document get`. A done or abandoned intent refuses with
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
| `plastic graph show ID --dry-run` | The files the render would write for the work graph. |
| `plastic intent unlink ID KIND TARGET --dry-run` | The links the removal would delete. |
| `plastic intent archive ID --dry-run` | The files the archive would remove, and the rows it keeps. |
| `plastic roadmap show SLUG --dry-run` | The files the state screen would write. |
| `plastic roadmap drop SLUG ITEM --dry-run` | The roadmap rows the dropped item would change. |
| `plastic roadmap edge remove SLUG FROM TO --dry-run` | The roadmap edge rows the removal would delete. |

`plastic sync up`, `plastic sync down`, `plastic intent revise` and `plastic backup` keep their own previews. `plastic backup --live` prints each line of the backup's `backup.log` as it is written. `plastic backup purge` (with `--older-than`, `--all` or `--failed`) and `plastic backup restore` take `--dry-run` and list what they would delete or put back. A restore asks nothing and ends with `next: plastic sync down --project STORE`.
`plastic uninstall --dry-run` lists every path the uninstall would remove.

## Installer commands

`plastic install`, `plastic update`, `plastic rollback` and `plastic uninstall` run the
installer scripts as child processes. A script that exits 3 makes the command exit 3, and any
other failure exits 1. See [INSTALL.md](../../INSTALL.md).

## Check the installation

| Command | Result |
| ------- | ------ |
| `plastic version` | The version, the release channel and the file the version came from. |
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
so it changes nothing. `--harness NAME` checks a named harness instead of the one the call runs
in.

## Help that costs nothing

`plastic help` reads one table and loads no command file. `plastic <command> --help` prints
the usage line without building the command. An unknown command prints the closest name.

## Exit codes

| Code | Meaning |
| ---- | ------- |
| 0 | Succeeded |
| 1 | Failed |
| 2 | Called wrongly |
| 3 | Refused, because the step belongs to the owner |

## Starts without Node

`bin/plastic` is a Ruby script. It uses the Ruby standard library only and loads with
RubyGems off. `install.sh` installs it from a GitHub release. In an installed release,
`bin/plastic` is a shell launcher that starts the release's own Ruby by its full path, so the
Ruby on your `PATH` does not matter.
