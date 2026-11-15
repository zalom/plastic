# plastic sync up

Read the files changed by hand into rows.

Reads the files people changed into rows. A record changed on both sides stops the call, exit 3, and every conflict is listed. With one home after the other and a copy of the files between, no change is lost; with a command on each home before the copy, the file that arrives takes the place of the change of the second home. An index that another home printed sets the title, the state, the disposition, the reason and the closed time of every intent it lists. So with a command on each home before the copy, it takes back a change of this home, also on an intent that the other home never changed. A file deleted on one home is printed again from rows on the other.

```sh
plastic sync up [--overwrite [PATH]] [--merge] [--dry-run]
```

The command is `Sync::Up`, in [`up.rb:15`](../../../../lib/plastic/commands/sync/up.rb#L15). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `--overwrite [PATH]` | read the file of the path into rows, or every file with no path | `false` |
| `--merge` | apply the one-sided changes, then list the conflicts | `false` |
| `--dry-run` | preview the complete sync in a disposable copy | `false` |

## Components

![The components on the path of plastic sync up](component.svg)

The figure shows the command, the workflows it runs, the classes behind them, and the databases and files they reach.

## The events of one call

![The workflows of plastic sync up](workflows.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [Code::Sync::Up::Preview](#codesyncuppreview) | code | [`preview.rb:13`](../../../../lib/plastic/workflows/code/sync/up/preview.rb#L13) |
| [Code::Sync::Up](#codesyncup) | code | [`up.rb:11`](../../../../lib/plastic/workflows/code/sync/up.rb#L11) |

### Code::Sync::Up::Preview

The code workflow `:code_preview_sync`, in [`preview.rb:13`](../../../../lib/plastic/workflows/code/sync/up/preview.rb#L13).

Previews the same sync in a copy before the normal write workflow, and refuses what the real run refuses.

![How Code::Sync::Up::Preview runs: its steps, where it stops, and its outcomes](code_preview_sync.svg)

Its rows run in this order:

1. Read: preview the sync in an isolated copy. [`preview.rb:44`](../../../../lib/plastic/workflows/code/sync/up/preview.rb#L44)
2. Gate: passes when `as_real?(context, :runs?)`; otherwise the call stops with exit 1 and prints FAILURE. [`preview.rb:55`](../../../../lib/plastic/workflows/code/sync/up/preview.rb#L55)
3. Gate: passes when `as_real?(context, :writes?)`; otherwise the call stops with exit 3 and prints changed on both sides since the last print, nothing written. --overwrite PATH reads that file into rows, --overwrite reads every file, --merge applies the one-sided changes and lists the rest. The records: CONFLICTS. [`preview.rb:64`](../../../../lib/plastic/workflows/code/sync/up/preview.rb#L64)
4. Gate: passes when `as_real?(context, :settled?)`; otherwise the call stops with exit 3 and prints changed on both sides since the last print, left as they are. --overwrite PATH reads that file into rows, --overwrite reads every file. The records: CONFLICTS. [`preview.rb:65`](../../../../lib/plastic/workflows/code/sync/up/preview.rb#L65)
5. Gate: passes when `as_real?(context, :readable?)`; otherwise the call stops with exit 1 and prints intent folders that could not be read, the others were read: UNREADABLE fix or remove each folder named, then run plastic sync up again. [`preview.rb:70`](../../../../lib/plastic/workflows/code/sync/up/preview.rb#L70)
6. Gate: passes when `as_real?(context, :files_read?)`; otherwise the call stops with exit 1 and prints files that cannot be read into rows, the others were read: UNREADABLE_FILES. [`preview.rb:71`](../../../../lib/plastic/workflows/code/sync/up/preview.rb#L71)
7. Gate: passes when `as_real?(context, :rowless_read?)`; otherwise the call stops with exit 1 and prints files that cannot be read into rows, the others were read: UNREADABLE_FILES. [`preview.rb:73`](../../../../lib/plastic/workflows/code/sync/up/preview.rb#L73)
8. Outcome `:done`, when `context.dry_run`: finishes with exit 0; next: ORIGINAL_COMMAND. [`preview.rb:50`](../../../../lib/plastic/workflows/code/sync/up/preview.rb#L50)
9. Outcome `:continue`, otherwise: starts the workflow [Code::Sync::Up](#codesyncup). [`preview.rb:51`](../../../../lib/plastic/workflows/code/sync/up/preview.rb#L51)

It sets `failure`, `conflicts`, `merging`, `unreadable`, `unreadable_files`, `unreadable_path`, `unreadable_rowless`.

### Code::Sync::Up

The code workflow `:code_sync_up`, in [`up.rb:11`](../../../../lib/plastic/workflows/code/sync/up.rb#L11).

Sync up: plans, applies, and refuses on the conflicts left.

![How Code::Sync::Up runs: its steps, where it stops, and its outcomes](code_sync_up.svg)

Its rows run in this order:

1. Read: plan the sync. [`sync_steps.rb:116`](../../../../lib/plastic/workflows/sync_steps.rb#L116)
2. Gate: passes when `public_send(name, context)`; otherwise the call stops with exit 1 and prints FAILURE. [`sync_steps.rb:117`](../../../../lib/plastic/workflows/sync_steps.rb#L117)
3. Gate: passes when `public_send(name, context)`; otherwise the call stops with exit 3 and prints changed on both sides since the last print, nothing written. --overwrite PATH reads that file into rows, --overwrite reads every file, --merge applies the one-sided changes and lists the rest. The records: CONFLICTS. [`sync_steps.rb:108`](../../../../lib/plastic/workflows/sync_steps.rb#L108)
4. Step: apply the changes. Done when `plan(context, direction).pending.zero?`, so a second call skips it. [`sync_steps.rb:124`](../../../../lib/plastic/workflows/sync_steps.rb#L124)
5. Read: say what changed. [`sync_steps.rb:125`](../../../../lib/plastic/workflows/sync_steps.rb#L125)
6. Gate: passes when `public_send(name, context)`; otherwise the call stops with exit 3 and prints changed on both sides since the last print, left as they are. --overwrite PATH reads that file into rows, --overwrite reads every file. The records: CONFLICTS. [`sync_steps.rb:108`](../../../../lib/plastic/workflows/sync_steps.rb#L108)
7. Gate: passes when `public_send(name, context)`; otherwise the call stops with exit 1 and prints intent folders that could not be read, the others were read: UNREADABLE fix or remove each folder named, then run plastic sync up again. [`sync_steps.rb:108`](../../../../lib/plastic/workflows/sync_steps.rb#L108)
8. Gate: passes when `public_send(name, context)`; otherwise the call stops with exit 1 and prints files that cannot be read into rows, the others were read: UNREADABLE_FILES. [`sync_steps.rb:109`](../../../../lib/plastic/workflows/sync_steps.rb#L109)
9. Gate: passes when `public_send(name, context)`; otherwise the call stops with exit 1 and prints files that cannot be read into rows, the others were read: UNREADABLE_FILES. [`sync_steps.rb:109`](../../../../lib/plastic/workflows/sync_steps.rb#L109)
10. Outcome `:done`, always: finishes with exit 0; next: plastic next. [`sync_steps.rb:104`](../../../../lib/plastic/workflows/sync_steps.rb#L104)

It sets `failure`, `conflicts`, `merging`, `unreadable`, `unreadable_files`, `unreadable_path`, `unreadable_rowless`, `lines`.

In the words of workflow engines, the rows are these four parts:

- **Trigger**: the call starts the workflow `Code::Sync::Up::Preview`; each later workflow starts from an outcome of the one before it.
- **Activities**: 3 reads and 1 step.
- **Transitions**: 12 gates stop the call when their checks fail; a step runs only while its done check fails; Preview goes to Up on `:continue`.
- **Outcomes**: `:done` of Preview, `:done` of Up end the call.

## What one call reads, writes and prints

![What one call of plastic sync up reads, writes and prints](touches.svg)

| Place | Database or file | Tables | Reads or writes | Code |
| --- | --- | --- | --- | --- |
| the store folder | knowledge_graph.db | not found in the code | writes | [`sync_options.rb:16`](../../../../lib/plastic/cli/sync_options.rb#L16) |
| the store folder | references.db | not found in the code | writes | [`sync_options.rb:16`](../../../../lib/plastic/cli/sync_options.rb#L16) |
| the store folder | work_graph.db | `archives`, `batches`, `completions`, `intents`, `roadmap_edges`, `roadmap_items`, `roadmap_log`, `roadmaps` | reads and writes | [`sync_options.rb:16`](../../../../lib/plastic/cli/sync_options.rb#L16) |

A second call runs the same rows again. A step runs again only when its done check fails.

| Step | Done when | The second call | Code |
| --- | --- | --- | --- |
| apply the changes | `plan(context, direction).pending.zero?` | skips it | [`sync_steps.rb:124`](../../../../lib/plastic/workflows/sync_steps.rb#L124) |

## How a call ends

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| FAILURE | 1 | prints no next: line | [`preview.rb:55`](../../../../lib/plastic/workflows/code/sync/up/preview.rb#L55) |
| changed on both sides since the last print, nothing written. --overwrite PATH reads that file into rows, --overwrite reads every file, --merge applies the one-sided changes and lists the rest. The records: CONFLICTS | 3 | prints no next: line | [`preview.rb:64`](../../../../lib/plastic/workflows/code/sync/up/preview.rb#L64) |
| changed on both sides since the last print, left as they are. --overwrite PATH reads that file into rows, --overwrite reads every file. The records: CONFLICTS | 3 | prints no next: line | [`preview.rb:65`](../../../../lib/plastic/workflows/code/sync/up/preview.rb#L65) |
| intent folders that could not be read, the others were read: UNREADABLE fix or remove each folder named, then run plastic sync up again | 1 | prints no next: line | [`preview.rb:70`](../../../../lib/plastic/workflows/code/sync/up/preview.rb#L70) |
| files that cannot be read into rows, the others were read: UNREADABLE_FILES | 1 | plastic sync down --overwrite UNREADABLE_PATH | [`preview.rb:71`](../../../../lib/plastic/workflows/code/sync/up/preview.rb#L71) |
| files that cannot be read into rows, the others were read: UNREADABLE_FILES | 1 | prints no next: line | [`preview.rb:73`](../../../../lib/plastic/workflows/code/sync/up/preview.rb#L73) |
| the preview wrote only to a disposable copy | 0 | ORIGINAL_COMMAND | [`preview.rb:50`](../../../../lib/plastic/workflows/code/sync/up/preview.rb#L50) |
| FAILURE | 1 | prints no next: line | [`sync_steps.rb:117`](../../../../lib/plastic/workflows/sync_steps.rb#L117) |
| changed on both sides since the last print, nothing written. --overwrite PATH reads that file into rows, --overwrite reads every file, --merge applies the one-sided changes and lists the rest. The records: CONFLICTS | 3 | prints no next: line | [`sync_steps.rb:108`](../../../../lib/plastic/workflows/sync_steps.rb#L108) |
| changed on both sides since the last print, left as they are. --overwrite PATH reads that file into rows, --overwrite reads every file. The records: CONFLICTS | 3 | prints no next: line | [`sync_steps.rb:108`](../../../../lib/plastic/workflows/sync_steps.rb#L108) |
| intent folders that could not be read, the others were read: UNREADABLE fix or remove each folder named, then run plastic sync up again | 1 | prints no next: line | [`sync_steps.rb:108`](../../../../lib/plastic/workflows/sync_steps.rb#L108) |
| files that cannot be read into rows, the others were read: UNREADABLE_FILES | 1 | plastic sync down --overwrite UNREADABLE_PATH | [`sync_steps.rb:109`](../../../../lib/plastic/workflows/sync_steps.rb#L109) |
| files that cannot be read into rows, the others were read: UNREADABLE_FILES | 1 | prints no next: line | [`sync_steps.rb:109`](../../../../lib/plastic/workflows/sync_steps.rb#L109) |
| the rows hold every file changed by hand | 0 | plastic next | [`sync_steps.rb:104`](../../../../lib/plastic/workflows/sync_steps.rb#L104) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:108`](../../../../lib/plastic/code_workflow.rb#L108) |

## What the page leaves out

Every call shares a few things that this page does not repeat; [the command DSL](../../dsl/README.md#what-every-call-shares) names them.

- A call that writes saves a routine run row in local.db. A stop by a gate or a step saves the run, and the next call resumes from it. A dry run saves no row.
