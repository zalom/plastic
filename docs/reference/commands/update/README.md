# plastic update

Sync a newer package into the home or name the installer command.

Syncs a newer running package into the home, or activates the newest release of the chosen channel, by default the active release's own.

```sh
plastic update [--channel NAME] [--dry-run]
```

The command is `Update`, in [`update.rb:10`](../../../../lib/plastic/commands/update.rb#L10). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `--channel NAME` | update from this channel: stable, beta or alpha |  |
| `--dry-run` | name both versions and change nothing | `false` |

## What it touches

![What plastic update touches](component.svg)

## Before the chain

The command's own `call`, at [`update.rb:16`](../../../../lib/plastic/commands/update.rb#L16), runs first:

```ruby
def call
  channel = parsed[:channel]
  raise CLI::Command::Usage, "--channel takes stable, beta or alpha" unless [nil, *Workflows::ReleaseUpdate::CHANNELS.keys].include?(channel)

  super
end
```

## How the call flows

![The chain of workflows that plastic update runs](chain.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [Code::Update::Preview](#codeupdatepreview) | code | [`preview.rb:14`](../../../../lib/plastic/workflows/code/update/preview.rb#L14) |
| [Code::Update](#codeupdate) | code | [`update.rb:15`](../../../../lib/plastic/workflows/code/update.rb#L15) |

### Code::Update::Preview

The code workflow `:code_preview_update`, in [`preview.rb:14`](../../../../lib/plastic/workflows/code/update/preview.rb#L14).

Compares the installed version with the running package. A dry run names both and what the update would do.

![How Code::Update::Preview runs: its steps, where it stops, and its outcomes](code_preview_update.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| compare the installed and the running versions | read |  | [`preview.rb:19`](../../../../lib/plastic/workflows/code/update/preview.rb#L19) |
| Plastic is not installed under this home; run plastic install first | gate, stops with exit 3 | `!context.from.nil?` | [`preview.rb:25`](../../../../lib/plastic/workflows/code/update/preview.rb#L25) |
| say what the update would do | read |  | [`preview.rb:28`](../../../../lib/plastic/workflows/code/update/preview.rb#L28) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:done` | when `context.dry_run` | finishes, exit 0; next: %{original_command} | [`preview.rb:35`](../../../../lib/plastic/workflows/code/update/preview.rb#L35) |
| `:continue` | otherwise | runs [Code::Update](#codeupdate) | [`preview.rb:36`](../../../../lib/plastic/workflows/code/update/preview.rb#L36) |

It sets `from`, `to`.

### Code::Update

The code workflow `:code_update_plastic`, in [`update.rb:15`](../../../../lib/plastic/workflows/code/update.rb#L15).

Syncs a newer running package into the home for the registered agents. When the running package is not newer, activates the newest release of the chosen channel, or of the active release's channel, and syncs its files into the home. With no release activated yet, names the installer command that installs one.

![How Code::Update runs: its steps, where it stops, and its outcomes](code_update_plastic.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| check whether the running package is newer | read |  | [`update.rb:20`](../../../../lib/plastic/workflows/code/update.rb#L20) |
| sync the newer package into the home | step | `!context.newer \|\| context.synced` | [`update.rb:24`](../../../../lib/plastic/workflows/code/update.rb#L24) |
| find a newer release on the chosen channel | read |  | [`update.rb:32`](../../../../lib/plastic/workflows/code/update.rb#L32) |
| activate the newer release | step | `context.release.nil? \|\| context.activated` | [`update.rb:36`](../../../../lib/plastic/workflows/code/update.rb#L36) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:done` | when `context.synced` | finishes, exit 0; next: plastic version | [`update.rb:40`](../../../../lib/plastic/workflows/code/update.rb#L40) |
| `:activated` | when `context.activated` | finishes, exit 0; next: plastic version | [`update.rb:41`](../../../../lib/plastic/workflows/code/update.rb#L41) |
| `:current` | when `context.active` | finishes, exit 0; next: plastic version | [`update.rb:43`](../../../../lib/plastic/workflows/code/update.rb#L43) |
| `:fetch` | otherwise | finishes, exit 0; next: plastic update | [`update.rb:45`](../../../../lib/plastic/workflows/code/update.rb#L45) |

It sets `newer`, `synced`, `active`, `release`, `activated`.

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| Plastic is not installed under this home; run plastic install first | 3 | prints no next: line | [`preview.rb:25`](../../../../lib/plastic/workflows/code/update/preview.rb#L25) |
| the preview changed no file | 0 | %{original_command} | [`preview.rb:35`](../../../../lib/plastic/workflows/code/update/preview.rb#L35) |
| the home holds Plastic %{to} | 0 | plastic version | [`update.rb:40`](../../../../lib/plastic/workflows/code/update.rb#L40) |
| Plastic %{activated} is active and the home holds its files | 0 | plastic version | [`update.rb:41`](../../../../lib/plastic/workflows/code/update.rb#L41) |
| Plastic %{active} is the newest release on its channel | 0 | plastic version | [`update.rb:43`](../../../../lib/plastic/workflows/code/update.rb#L43) |
| run the installer command above, then update again | 0 | plastic update | [`update.rb:45`](../../../../lib/plastic/workflows/code/update.rb#L45) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |
| Usage error: --channel takes stable, beta or alpha | 2 | prints no next: line | [`update.rb:18`](../../../../lib/plastic/commands/update.rb#L18) |
