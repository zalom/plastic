# plastic backup list

List one store's backups with status and goal, flagging a missing or changed file.

```sh
plastic backup list --store SLUG
```

The command is `Backup::List`, in [`list.rb:11`](../../../../lib/plastic/commands/backup/list.rb#L11). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `--store SLUG` | the registered project whose backups the call works on |  |

## What it touches

![What plastic backup list touches](component.svg)

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

## How the call flows

![The chain of workflows that plastic backup list runs](chain.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [Code::Backup::List](#codebackuplist) | code | [`list.rb:12`](../../../../lib/plastic/workflows/code/backup/list.rb#L12) |

### Code::Backup::List

The code workflow `:code_backup_list`, in [`list.rb:12`](../../../../lib/plastic/workflows/code/backup/list.rb#L12).

Prints each backup folder of the store with its start time, status and goal, flagging a missing or changed file. A flag fails the call.

![How Code::Backup::List runs: its steps, where it stops, and its outcomes](code_backup_list.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| print each backup | read |  | [`list.rb:19`](../../../../lib/plastic/workflows/code/backup/list.rb#L19) |
| a backup is missing or changed; see above | gate, stops with exit 1 | `!context.flagged` | [`list.rb:32`](../../../../lib/plastic/workflows/code/backup/list.rb#L32) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:done` | always | finishes, exit 0; next: plastic backup --store %{store} | [`list.rb:34`](../../../../lib/plastic/workflows/code/backup/list.rb#L34) |

It sets `flagged`.

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| a backup is missing or changed; see above | 1 | prints no next: line | [`list.rb:32`](../../../../lib/plastic/workflows/code/backup/list.rb#L32) |
| every backup with a row is on disk and unchanged | 0 | plastic backup --store %{store} | [`list.rb:34`](../../../../lib/plastic/workflows/code/backup/list.rb#L34) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |
| Usage error: name the store with --store; --project does not apply | 2 | prints no next: line | [`backup_store.rb:27`](../../../../lib/plastic/commands/backup_store.rb#L27) |
| Usage error: no registered project named %{slug}; the projects are %{projects} | 2 | prints no next: line | [`backup_store.rb:35`](../../../../lib/plastic/commands/backup_store.rb#L35) |
