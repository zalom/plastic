# plastic uninstall

Remove Plastic from agents and keep the home.

Shows the harnesses Plastic is installed into or found in, with every recorded one picked, and removes what the record of each picked one lists. The home and its stores stay. See docs/help/choice-screen.md.

```sh
plastic uninstall [ANSWER] [--dry-run]
```

The command is `Uninstall`, in [`uninstall.rb:12`](../../../../lib/plastic/commands/uninstall.rb#L12). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ANSWER` | the person's answer to the numbered list | |
| `--dry-run` | list what would change and change nothing | `false` |

## What it touches

![What plastic uninstall touches](component.svg)

## Before the chain

The command's own `call`, at [`harness_pick.rb:12`](../../../../lib/plastic/commands/harness_pick.rb#L12), runs first:

```ruby
def call
  answer = parsed[:answer] ||= answered_on_screen
  super if answer
end
```

## How the call flows

![The chain of workflows that plastic uninstall runs](chain.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [Code::Uninstall::Choose](#codeuninstallchoose) | code | [`choose.rb:14`](../../../../lib/plastic/workflows/code/uninstall/choose.rb#L14) |
| [Code::Uninstall::Preview](#codeuninstallpreview) | code | [`preview.rb:16`](../../../../lib/plastic/workflows/code/uninstall/preview.rb#L16) |
| [Code::Uninstall](#codeuninstall) | code | [`uninstall.rb:14`](../../../../lib/plastic/workflows/code/uninstall.rb#L14) |

### Code::Uninstall::Choose

The code workflow `:code_choose_installations`, in [`choose.rb:14`](../../../../lib/plastic/workflows/code/uninstall/choose.rb#L14).

Reads the person's answer against the harnesses Plastic is installed into or found in.

![How Code::Uninstall::Choose runs: its steps, where it stops, and its outcomes](code_choose_installations.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| list the recorded and the found harnesses and read the person's answer | read |  | [`choose.rb:19`](../../../../lib/plastic/workflows/code/uninstall/choose.rb#L19) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:none` | when `context.found.empty?` | finishes, exit 0; next: plastic init | [`choose.rb:28`](../../../../lib/plastic/workflows/code/uninstall/choose.rb#L28) |
| `:left` | when `context.picked.empty?` | finishes, exit 0; next: plastic uninstall | [`choose.rb:30`](../../../../lib/plastic/workflows/code/uninstall/choose.rb#L30) |
| `:chosen` | otherwise | runs [Code::Uninstall::Preview](#codeuninstallpreview) | [`choose.rb:32`](../../../../lib/plastic/workflows/code/uninstall/choose.rb#L32) |

It sets `found`, `picked`, `harnesses`.

### Code::Uninstall::Preview

The code workflow `:code_preview_uninstall`, in [`preview.rb:16`](../../../../lib/plastic/workflows/code/uninstall/preview.rb#L16).

On a dry run, lists what the record of each picked harness names, the releases and the launcher among them when no harness stays installed, and the home it keeps.

![How Code::Uninstall::Preview runs: its steps, where it stops, and its outcomes](code_preview_uninstall.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| list what the uninstall would remove or change | read |  | [`preview.rb:19`](../../../../lib/plastic/workflows/code/uninstall/preview.rb#L19) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:done` | when `context.dry_run` | finishes, exit 0; next: %{original_command} | [`preview.rb:29`](../../../../lib/plastic/workflows/code/uninstall/preview.rb#L29) |
| `:continue` | otherwise | runs [Code::Uninstall](#codeuninstall) | [`preview.rb:31`](../../../../lib/plastic/workflows/code/uninstall/preview.rb#L31) |

### Code::Uninstall

The code workflow `:code_uninstall_plastic`, in [`uninstall.rb:14`](../../../../lib/plastic/workflows/code/uninstall.rb#L14).

Removes what the record of each picked harness lists, then the releases and the launcher once no harness stays installed. The home with its stores stays.

![How Code::Uninstall runs: its steps, where it stops, and its outcomes](code_uninstall_plastic.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| remove what each record lists | step | `context.removed` | [`uninstall.rb:21`](../../../../lib/plastic/workflows/code/uninstall.rb#L21) |
| remove the releases and the launcher | step | `context.releases_removed` | [`uninstall.rb:30`](../../../../lib/plastic/workflows/code/uninstall.rb#L30) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:done` | always | finishes, exit 0; next: plastic init | [`uninstall.rb:37`](../../../../lib/plastic/workflows/code/uninstall.rb#L37) |

It sets `removed`, `releases_removed`.

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| Plastic is installed into no harness and no registered harness was found | 0 | plastic init | [`choose.rb:28`](../../../../lib/plastic/workflows/code/uninstall/choose.rb#L28) |
| the person left with no change | 0 | plastic uninstall | [`choose.rb:30`](../../../../lib/plastic/workflows/code/uninstall/choose.rb#L30) |
| the preview changed no file | 0 | %{original_command} | [`preview.rb:29`](../../../../lib/plastic/workflows/code/uninstall/preview.rb#L29) |
| Plastic is removed from %{harnesses}; the home stays | 0 | plastic init | [`uninstall.rb:37`](../../../../lib/plastic/workflows/code/uninstall.rb#L37) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |
