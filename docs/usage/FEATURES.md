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
`doctor` reads the flag itself and prints its report as a JSON document. The keys are stable, so
a script can read them.

## Scope

A command works on one store. A project named with `--project SLUG` wins. With no name, the
project whose repository holds the current directory wins, and an inner repository beats an
outer one. With neither, the global store answers.

## Session commands

| Command | Result |
| ------- | ------ |
| `plastic status` | Active work in every store. |
| `plastic continue` | Where one project stands, and what runs next. |
| `plastic next` | The next action in one line. `--why` adds the rule behind it. |

`continue` and `next` read the same frontier: the liveliest roadmap, its open batch, and the
entries that are ready, in flight or blocked. With no roadmap, both name the first active
intent instead.

## Installer commands

`plastic install`, `plastic update`, `plastic rollback` and `plastic uninstall` run the
installer scripts as child processes. A script that exits 3 makes the command exit 3, and any
other failure exits 1. See [INSTALL.md](../../INSTALL.md).

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
RubyGems off. npm remains one way to install it.
