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

## What it touches

![What plastic rollback touches](component.svg)

## How the call flows

![The chain of workflows that plastic rollback runs](chain.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [Code::Rollback::Preview](#coderollbackpreview) | code | [`preview.rb:13`](../../../../lib/plastic/workflows/code/rollback/preview.rb#L13) |
| [Code::Rollback](#coderollback) | code | [`rollback.rb:11`](../../../../lib/plastic/workflows/code/rollback.rb#L11) |

### Code::Rollback::Preview

The code workflow `:code_preview_rollback`, in [`preview.rb:13`](../../../../lib/plastic/workflows/code/rollback/preview.rb#L13).

Reads the activated releases and picks the one to switch to: the named version, or the previous release. A dry run names the switch.

![How Code::Rollback::Preview runs: its steps, where it stops, and its outcomes](code_preview_rollback.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| read the activated releases | read |  | [`preview.rb:18`](../../../../lib/plastic/workflows/code/rollback/preview.rb#L18) |
| no release is installed under this home; install one with install.sh first | gate, stops with exit 3 | `context.active` | [`preview.rb:25`](../../../../lib/plastic/workflows/code/rollback/preview.rb#L25) |
| %{target} is not installed | gate, stops with exit 3 | `context.target.nil? \|\| context.releases.include?(context.target)` | [`preview.rb:27`](../../../../lib/plastic/workflows/code/rollback/preview.rb#L27) |
| no previous release to go back to | gate, stops with exit 3 | `context.to` | [`preview.rb:29`](../../../../lib/plastic/workflows/code/rollback/preview.rb#L29) |
| say what the rollback would do | read |  | [`preview.rb:31`](../../../../lib/plastic/workflows/code/rollback/preview.rb#L31) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:done` | when `context.dry_run` | finishes, exit 0; next: %{original_command} | [`preview.rb:39`](../../../../lib/plastic/workflows/code/rollback/preview.rb#L39) |
| `:continue` | otherwise | runs [Code::Rollback](#coderollback) | [`preview.rb:40`](../../../../lib/plastic/workflows/code/rollback/preview.rb#L40) |

It sets `active`, `to`, `releases`.

### Code::Rollback

The code workflow `:code_rollback_release`, in [`rollback.rb:11`](../../../../lib/plastic/workflows/code/rollback.rb#L11).

Switches the active pointer to the named release or the previous one, and syncs that release's files into the home in the same activation.

![How Code::Rollback runs: its steps, where it stops, and its outcomes](code_rollback_release.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| switch the active release | step | `context.switched` | [`rollback.rb:16`](../../../../lib/plastic/workflows/code/rollback.rb#L16) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:done` | always | finishes, exit 0; next: plastic version | [`rollback.rb:21`](../../../../lib/plastic/workflows/code/rollback.rb#L21) |

It sets `switched`.

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| no release is installed under this home; install one with install.sh first | 3 | prints no next: line | [`preview.rb:25`](../../../../lib/plastic/workflows/code/rollback/preview.rb#L25) |
| %{target} is not installed | 3 | prints no next: line | [`preview.rb:27`](../../../../lib/plastic/workflows/code/rollback/preview.rb#L27) |
| no previous release to go back to | 3 | prints no next: line | [`preview.rb:29`](../../../../lib/plastic/workflows/code/rollback/preview.rb#L29) |
| the preview changed no file | 0 | %{original_command} | [`preview.rb:39`](../../../../lib/plastic/workflows/code/rollback/preview.rb#L39) |
| Plastic %{switched} is active and the home holds its files | 0 | plastic version | [`rollback.rb:21`](../../../../lib/plastic/workflows/code/rollback.rb#L21) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |
