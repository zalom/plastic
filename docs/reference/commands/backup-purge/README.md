# plastic backup purge

Delete one store's backups; give one of --all, --failed or --older-than.

Deletes backups of one registered store: all of them, those before a date, or those that failed.

```sh
plastic backup purge --store SLUG (--older-than DATE | --all | --failed) [--dry-run]
```

The command is `Backup::Purge`, in [`purge.rb:12`](../../../../lib/plastic/commands/backup/purge.rb#L12). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `--store SLUG` | the registered project whose backups the call works on |  |
| `--older-than DATE` | delete the backups before this date or time |  |
| `--all` | delete every backup of the store | `false` |
| `--failed` | delete every backup whose status is failed | `false` |
| `--dry-run` | list what would be deleted and delete nothing | `false` |

## What it touches

![What plastic backup purge touches](component.svg)

## Before the chain

The command's own `call`, at [`backup_store.rb:15`](../../../../lib/plastic/commands/backup_store.rb#L15), runs first:

```ruby
def call
  refuse_project
  refuse_unregistered
  check_call
  super
end
```

The command's own `check_call`, at [`purge.rb:32`](../../../../lib/plastic/commands/backup/purge.rb#L32), runs inside it:

```ruby
def check_call
  one_of(%i[older_than all failed], give: "give --older-than DATE, --all or --failed", both: "--older-than, --all and --failed exclude each other")
  read_date
end
```

## How the call flows

![The chain of workflows that plastic backup purge runs](chain.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [Code::Backup::Purge::Preview](#codebackuppurgepreview) | code | [`preview.rb:12`](../../../../lib/plastic/workflows/code/backup/purge/preview.rb#L12) |
| [Code::Backup::Purge](#codebackuppurge) | code | [`purge.rb:13`](../../../../lib/plastic/workflows/code/backup/purge.rb#L13) |

### Code::Backup::Purge::Preview

The code workflow `:code_preview_backup_purge`, in [`preview.rb:12`](../../../../lib/plastic/workflows/code/backup/purge/preview.rb#L12).

Lists the backups a purge would delete, and deletes nothing.

![How Code::Backup::Purge::Preview runs: its steps, where it stops, and its outcomes](code_preview_backup_purge.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| preview the purge | read |  | [`preview.rb:15`](../../../../lib/plastic/workflows/code/backup/purge/preview.rb#L15) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:done` | when `context.dry_run` | finishes, exit 0; next: %{original_command} | [`preview.rb:22`](../../../../lib/plastic/workflows/code/backup/purge/preview.rb#L22) |
| `:continue` | otherwise | runs [Code::Backup::Purge](#codebackuppurge) | [`preview.rb:24`](../../../../lib/plastic/workflows/code/backup/purge/preview.rb#L24) |

### Code::Backup::Purge

The code workflow `:code_backup_purge`, in [`purge.rb:13`](../../../../lib/plastic/workflows/code/backup/purge.rb#L13).

Deletes the backup folders of one store with their rows: all of them, or those strictly before a time, or those that failed. A row with no folder goes with them.

![How Code::Backup::Purge runs: its steps, where it stops, and its outcomes](code_backup_purge.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| delete the backups | step | `!context.purged.nil?` | [`purge.rb:28`](../../../../lib/plastic/workflows/code/backup/purge.rb#L28) |
| say what was deleted | read |  | [`purge.rb:35`](../../../../lib/plastic/workflows/code/backup/purge.rb#L35) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:done` | always | finishes, exit 0; next: plastic backup list --store %{store} | [`purge.rb:40`](../../../../lib/plastic/workflows/code/backup/purge.rb#L40) |

It sets `purged`.

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| the preview deleted nothing | 0 | %{original_command} | [`preview.rb:22`](../../../../lib/plastic/workflows/code/backup/purge/preview.rb#L22) |
| the backups named above are gone | 0 | plastic backup list --store %{store} | [`purge.rb:40`](../../../../lib/plastic/workflows/code/backup/purge.rb#L40) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |
| Usage error: name the store with --store; --project does not apply | 2 | prints no next: line | [`backup_store.rb:27`](../../../../lib/plastic/commands/backup_store.rb#L27) |
| Usage error: no registered project named %{slug}; the projects are %{projects} | 2 | prints no next: line | [`backup_store.rb:35`](../../../../lib/plastic/commands/backup_store.rb#L35) |
| Usage error | 2 | prints no next: line | [`backup_store.rb:40`](../../../../lib/plastic/commands/backup_store.rb#L40) |
| Usage error | 2 | prints no next: line | [`backup_store.rb:41`](../../../../lib/plastic/commands/backup_store.rb#L41) |
| Usage error | 2 | prints no next: line | [`backup_store.rb:47`](../../../../lib/plastic/commands/backup_store.rb#L47) |
