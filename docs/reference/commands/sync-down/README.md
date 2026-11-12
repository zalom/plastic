# plastic sync down

Write the rows that changed into files.

Writes the rows that changed into files. A record changed on both sides stops the call, exit 3, and every conflict is listed.

```sh
plastic sync down [--overwrite [PATH]] [--merge] [--dry-run]
```

The command is `Sync::Down`, in [`down.rb:12`](../../../../lib/plastic/commands/sync/down.rb#L12). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `--overwrite [PATH]` | settle conflicts on this side: one record by its path, or every record with no path | `false` |
| `--merge` | apply the one-sided changes, then list the conflicts | `false` |
| `--dry-run` | preview the complete sync in a disposable copy | `false` |

## Components

![The components on the path of plastic sync down](component.svg)

The figure shows the command, the workflows it runs, the classes behind them, and the databases and files they reach.

## The events of one call

![The workflows of plastic sync down](workflows.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [Code::Sync::Down::Preview](#codesyncdownpreview) | code | [`preview.rb:12`](../../../../lib/plastic/workflows/code/sync/down/preview.rb#L12) |
| [Code::Sync::Down](#codesyncdown) | code | [`down.rb:11`](../../../../lib/plastic/workflows/code/sync/down.rb#L11) |

### Code::Sync::Down::Preview

The code workflow `:code_preview_sync_down`, in [`preview.rb:12`](../../../../lib/plastic/workflows/code/sync/down/preview.rb#L12).

Previews sync down in a copy before the normal write workflow.

![How Code::Sync::Down::Preview runs: its steps, where it stops, and its outcomes](code_preview_sync_down.svg)

Its rows run in this order:

1. Read: preview the sync. [`preview.rb:15`](../../../../lib/plastic/workflows/code/sync/down/preview.rb#L15)
2. Outcome `:done`, when `context.dry_run`: finishes with exit 0; next: ORIGINAL_COMMAND. [`preview.rb:23`](../../../../lib/plastic/workflows/code/sync/down/preview.rb#L23)
3. Outcome `:continue`, otherwise: starts the workflow [Code::Sync::Down](#codesyncdown). [`preview.rb:25`](../../../../lib/plastic/workflows/code/sync/down/preview.rb#L25)

### Code::Sync::Down

The code workflow `:code_sync_down`, in [`down.rb:11`](../../../../lib/plastic/workflows/code/sync/down.rb#L11).

Sync down: plans, applies, and refuses on the conflicts left.

![How Code::Sync::Down runs: its steps, where it stops, and its outcomes](code_sync_down.svg)

Its rows run in this order:

1. Read: plan the sync. [`sync_steps.rb:67`](../../../../lib/plastic/workflows/sync_steps.rb#L67)
2. Gate: passes when `public_send(name, context)`; otherwise the call stops with exit 1 and prints FAILURE. [`sync_steps.rb:68`](../../../../lib/plastic/workflows/sync_steps.rb#L68)
3. Gate: passes when `public_send(name, context)`; otherwise the call stops with exit 3 and prints changed on both sides since the last print, nothing written: CONFLICTS; pass --overwrite PATH, --overwrite or --merge. [`sync_steps.rb:69`](../../../../lib/plastic/workflows/sync_steps.rb#L69)
4. Step: apply the changes. Done when `plan(context, direction).pending.zero?`, so a second call skips it. [`sync_steps.rb:73`](../../../../lib/plastic/workflows/sync_steps.rb#L73)
5. Read: say what changed. [`sync_steps.rb:74`](../../../../lib/plastic/workflows/sync_steps.rb#L74)
6. Gate: passes when `public_send(name, context)`; otherwise the call stops with exit 3 and prints changed on both sides since the last print, left as they are: CONFLICTS; pass --overwrite PATH or --overwrite. [`sync_steps.rb:75`](../../../../lib/plastic/workflows/sync_steps.rb#L75)
7. Outcome `:done`, always: finishes with exit 0; next: plastic next. [`sync_steps.rb:63`](../../../../lib/plastic/workflows/sync_steps.rb#L63)

It sets `failure`, `conflicts`, `merging`, `unreadable`, `lines`.

In the words of workflow engines, the rows are these four parts:

- **Trigger**: the call starts the workflow `Code::Sync::Down::Preview`; each later workflow starts from an outcome of the one before it.
- **Activities**: 3 reads and 1 step.
- **Transitions**: 3 gates stop the call when their checks fail; a step runs only while its done check fails; Preview goes to Down on `:continue`.
- **Outcomes**: `:done` of Preview, `:done` of Down end the call.

## What one call reads, writes and prints

![What one call of plastic sync down reads, writes and prints](touches.svg)

| Place | Database or file | Tables | Reads or writes | Code |
| --- | --- | --- | --- | --- |
| the store folder | knowledge_graph.db | `documents`, `legacy_intents_data`, `links`, `rulings` | reads and writes | [`sync_options.rb:12`](../../../../lib/plastic/cli/sync_options.rb#L12) |
| the store folder | references.db | `sqlar` | writes | [`sync_options.rb:12`](../../../../lib/plastic/cli/sync_options.rb#L12) |
| the store folder | work_graph.db | `clusters`, `intents`, `roadmap_edges`, `roadmap_items`, `roadmap_log`, `roadmaps`, `savepoints` | reads and writes | [`sync_options.rb:12`](../../../../lib/plastic/cli/sync_options.rb#L12) |

A second call runs the same rows again. A step runs again only when its done check fails.

| Step | Done when | The second call | Code |
| --- | --- | --- | --- |
| apply the changes | `plan(context, direction).pending.zero?` | skips it | [`sync_steps.rb:73`](../../../../lib/plastic/workflows/sync_steps.rb#L73) |

## How a call ends

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| the preview wrote only to a disposable copy | 0 | ORIGINAL_COMMAND | [`preview.rb:23`](../../../../lib/plastic/workflows/code/sync/down/preview.rb#L23) |
| FAILURE | 1 | prints no next: line | [`sync_steps.rb:68`](../../../../lib/plastic/workflows/sync_steps.rb#L68) |
| changed on both sides since the last print, nothing written: CONFLICTS; pass --overwrite PATH, --overwrite or --merge | 3 | prints no next: line | [`sync_steps.rb:69`](../../../../lib/plastic/workflows/sync_steps.rb#L69) |
| changed on both sides since the last print, left as they are: CONFLICTS; pass --overwrite PATH or --overwrite | 3 | prints no next: line | [`sync_steps.rb:75`](../../../../lib/plastic/workflows/sync_steps.rb#L75) |
| the files hold every row that changed | 0 | plastic next | [`sync_steps.rb:63`](../../../../lib/plastic/workflows/sync_steps.rb#L63) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |

## What the page leaves out

Every call shares a few things that this page does not repeat; [the command DSL](../../dsl/README.md#what-every-call-shares) names them.

- A call that writes saves a routine run row in local.db. A stop by a gate or a step saves the run, and the next call resumes from it. A dry run saves no row.
