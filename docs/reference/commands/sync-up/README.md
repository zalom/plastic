# plastic sync up

Read the files changed by hand into rows.

Reads the files people changed into rows. A record changed on both sides stops the call, exit 3, and every conflict is listed.

```sh
plastic sync up [--overwrite [PATH]] [--merge] [--dry-run]
```

The command is `SyncUp`, in [`sync_up.rb:11`](../../../../scripts/lib/plastic/commands/sync_up.rb#L11). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `--overwrite [PATH]` | settle conflicts on this side: one record by its path, or every record with no path | `false` |
| `--merge` | apply the one-sided changes, then list the conflicts | `false` |
| `--dry-run` | preview the complete sync in a disposable copy | `false` |

## What it touches

![What plastic sync up touches](component.svg)

## How the call flows

![The chain of workflows that plastic sync up runs](chain.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [PreviewSync](#previewsync) | code | [`preview_sync.rb:8`](../../../../scripts/lib/plastic/workflows/preview_sync.rb#L8) |
| [SyncUp](#syncup) | code | [`sync_up.rb:9`](../../../../scripts/lib/plastic/workflows/sync_up.rb#L9) |

### PreviewSync

The code workflow `:code_preview_sync`, in [`preview_sync.rb:8`](../../../../scripts/lib/plastic/workflows/preview_sync.rb#L8).

Previews the same sync in a copy before the normal write workflow.

![How PreviewSync runs: its steps, where it stops, and its outcomes](code_preview_sync.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| preview the sync in an isolated copy | read |  | [`preview_sync.rb:11`](../../../../scripts/lib/plastic/workflows/preview_sync.rb#L11) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:done` | when `context.dry_run` | finishes, exit 0; next: %{original_command} | [`preview_sync.rb:18`](../../../../scripts/lib/plastic/workflows/preview_sync.rb#L18) |
| `:continue` | otherwise | runs [SyncUp](#syncup) | [`preview_sync.rb:20`](../../../../scripts/lib/plastic/workflows/preview_sync.rb#L20) |

### SyncUp

The code workflow `:code_sync_up`, in [`sync_up.rb:9`](../../../../scripts/lib/plastic/workflows/sync_up.rb#L9).

Sync up: plans, applies, and refuses on the conflicts left.

![How SyncUp runs: its steps, where it stops, and its outcomes](code_sync_up.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| plan the sync | read |  | [`sync_steps.rb:67`](../../../../scripts/lib/plastic/workflows/sync_steps.rb#L67) |
| %{failure} | gate, stops with exit 1 | `public_send(name, context)` | [`sync_steps.rb:68`](../../../../scripts/lib/plastic/workflows/sync_steps.rb#L68) |
| changed on both sides since the last print, nothing written: %{conflicts}; pass --overwrite PATH, --overwrite or --merge | gate, stops with exit 3 | `public_send(name, context)` | [`sync_steps.rb:69`](../../../../scripts/lib/plastic/workflows/sync_steps.rb#L69) |
| apply the changes | step | `plan(context, direction).pending.zero?` | [`sync_steps.rb:73`](../../../../scripts/lib/plastic/workflows/sync_steps.rb#L73) |
| say what changed | read |  | [`sync_steps.rb:74`](../../../../scripts/lib/plastic/workflows/sync_steps.rb#L74) |
| changed on both sides since the last print, left as they are: %{conflicts}; pass --overwrite PATH or --overwrite | gate, stops with exit 3 | `public_send(name, context)` | [`sync_steps.rb:75`](../../../../scripts/lib/plastic/workflows/sync_steps.rb#L75) |
| intent folders that could not be read, the others were read:
%{unreadable}
fix or remove each folder named, then run plastic sync up again | gate, stops with exit 1 | `public_send(name, context)` | [`sync_steps.rb:62`](../../../../scripts/lib/plastic/workflows/sync_steps.rb#L62) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:done` | always | finishes, exit 0; next: plastic next | [`sync_steps.rb:63`](../../../../scripts/lib/plastic/workflows/sync_steps.rb#L63) |

It sets `failure`, `conflicts`, `merging`, `unreadable`, `lines`.

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| the preview wrote only to a disposable copy | 0 | %{original_command} | [`preview_sync.rb:18`](../../../../scripts/lib/plastic/workflows/preview_sync.rb#L18) |
| %{failure} | 1 | prints no next: line | [`sync_steps.rb:68`](../../../../scripts/lib/plastic/workflows/sync_steps.rb#L68) |
| changed on both sides since the last print, nothing written: %{conflicts}; pass --overwrite PATH, --overwrite or --merge | 3 | prints no next: line | [`sync_steps.rb:69`](../../../../scripts/lib/plastic/workflows/sync_steps.rb#L69) |
| changed on both sides since the last print, left as they are: %{conflicts}; pass --overwrite PATH or --overwrite | 3 | prints no next: line | [`sync_steps.rb:75`](../../../../scripts/lib/plastic/workflows/sync_steps.rb#L75) |
| intent folders that could not be read, the others were read:
%{unreadable}
fix or remove each folder named, then run plastic sync up again | 1 | prints no next: line | [`sync_steps.rb:62`](../../../../scripts/lib/plastic/workflows/sync_steps.rb#L62) |
| the rows hold every file changed by hand | 0 | plastic next | [`sync_steps.rb:63`](../../../../scripts/lib/plastic/workflows/sync_steps.rb#L63) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../scripts/lib/plastic/code_workflow.rb#L102) |
