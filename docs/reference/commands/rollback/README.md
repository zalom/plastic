# plastic rollback

Switch the active release back to the previous one or to a named installed one.

```sh
plastic rollback [--version VERSION] [--dry-run]
```

The command is `Rollback`, in [`rollback.rb:9`](../../../../lib/plastic/commands/rollback.rb#L9). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `--version VERSION` | an installed release to switch to |  |
| `--dry-run` | name the switch and change nothing | `false` |

## Components

![The components on the path of plastic rollback](component.svg)

The figure shows the command, the workflows it runs, the classes behind them, and the databases and files they reach.

## The events of one call

![The workflows of plastic rollback](workflows.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [Code::Rollback::Preview](#coderollbackpreview) | code | [`preview.rb:13`](../../../../lib/plastic/workflows/code/rollback/preview.rb#L13) |
| [Code::Rollback](#coderollback) | code | [`rollback.rb:12`](../../../../lib/plastic/workflows/code/rollback.rb#L12) |

### Code::Rollback::Preview

The code workflow `:code_preview_rollback`, in [`preview.rb:13`](../../../../lib/plastic/workflows/code/rollback/preview.rb#L13).

Reads the activated releases and picks the one to switch to: the named version, or the previous release. A dry run names the switch.

![How Code::Rollback::Preview runs: its steps, where it stops, and its outcomes](code_preview_rollback.svg)

Its rows run in this order:

1. Read: read the activated releases. [`preview.rb:19`](../../../../lib/plastic/workflows/code/rollback/preview.rb#L19)
2. Gate: passes when `context.active`; otherwise the call stops with exit 3 and prints no release is installed under this home; install one with install.sh first. [`preview.rb:26`](../../../../lib/plastic/workflows/code/rollback/preview.rb#L26)
3. Gate: passes when `context.target.nil? || context.releases.include?(context.target)`; otherwise the call stops with exit 3 and prints TARGET is not installed. [`preview.rb:28`](../../../../lib/plastic/workflows/code/rollback/preview.rb#L28)
4. Gate: passes when `context.to`; otherwise the call stops with exit 3 and prints no previous release to go back to. [`preview.rb:30`](../../../../lib/plastic/workflows/code/rollback/preview.rb#L30)
5. Read: say what the rollback would do. [`preview.rb:32`](../../../../lib/plastic/workflows/code/rollback/preview.rb#L32)
6. Outcome `:done`, when `context.dry_run`: finishes with exit 0; next: ORIGINAL_COMMAND. [`preview.rb:40`](../../../../lib/plastic/workflows/code/rollback/preview.rb#L40)
7. Outcome `:continue`, otherwise: starts the workflow [Code::Rollback](#coderollback). [`preview.rb:41`](../../../../lib/plastic/workflows/code/rollback/preview.rb#L41)

It sets `active`, `to`, `releases`.

### Code::Rollback

The code workflow `:code_rollback_release`, in [`rollback.rb:12`](../../../../lib/plastic/workflows/code/rollback.rb#L12).

Names the command that switches to the named release or the previous one. It changes nothing itself.

![How Code::Rollback runs: its steps, where it stops, and its outcomes](code_rollback_release.svg)

Its rows run in this order:

1. Read: name the switch command. [`rollback.rb:18`](../../../../lib/plastic/workflows/code/rollback.rb#L18)
2. Read: say what a rollback means for the stored data. [`rollback.rb:23`](../../../../lib/plastic/workflows/code/rollback.rb#L23)
3. Outcome `:done`, always: finishes with exit 0; next: COMMAND. [`rollback.rb:27`](../../../../lib/plastic/workflows/code/rollback.rb#L27)

It sets `command`.

In the words of workflow engines, the rows are these four parts:

- **Trigger**: the call starts the workflow `Code::Rollback::Preview`; each later workflow starts from an outcome of the one before it.
- **Activities**: 4 reads.
- **Transitions**: 3 gates stop the call when their checks fail; Preview goes to Rollback on `:continue`.
- **Outcomes**: `:done` of Preview, `:done` of Rollback end the call.

## What one call reads, writes and prints

![What one call of plastic rollback reads, writes and prints](touches.svg)

It reads and writes no store database and prints no store file.

## How a call ends

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| no release is installed under this home; install one with install.sh first | 3 | prints no next: line | [`preview.rb:26`](../../../../lib/plastic/workflows/code/rollback/preview.rb#L26) |
| TARGET is not installed | 3 | prints no next: line | [`preview.rb:28`](../../../../lib/plastic/workflows/code/rollback/preview.rb#L28) |
| no previous release to go back to | 3 | prints no next: line | [`preview.rb:30`](../../../../lib/plastic/workflows/code/rollback/preview.rb#L30) |
| the preview changed no file | 0 | ORIGINAL_COMMAND | [`preview.rb:40`](../../../../lib/plastic/workflows/code/rollback/preview.rb#L40) |
| this command switches the active release; rollback changed nothing | 0 | COMMAND | [`rollback.rb:27`](../../../../lib/plastic/workflows/code/rollback.rb#L27) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:108`](../../../../lib/plastic/code_workflow.rb#L108) |

## What the page leaves out

Every call shares a few things that this page does not repeat; [the command DSL](../../dsl/README.md#what-every-call-shares) names them.
