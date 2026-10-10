# plastic uninstall

Remove Plastic from agents and keep the home.

```sh
plastic uninstall [--claude] [--codex] [--hermes] [--all] [--dry-run]
```

The command is `Uninstall`, in [`uninstall.rb:10`](../../../../scripts/lib/plastic/commands/uninstall.rb#L10). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `--claude` | Claude Code, the default | `false` |
| `--codex` | Codex CLI | `false` |
| `--hermes` | Hermes | `false` |
| `--all` | every agent | `false` |
| `--dry-run` | list what would change and change nothing | `false` |

## What it touches

![What plastic uninstall touches](component.svg)

## How the call flows

![The chain of workflows that plastic uninstall runs](chain.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [PreviewUninstall](#previewuninstall) | code | [`preview_uninstall.rb:12`](../../../../scripts/lib/plastic/workflows/preview_uninstall.rb#L12) |
| [UninstallPlastic](#uninstallplastic) | code | [`uninstall_plastic.rb:12`](../../../../scripts/lib/plastic/workflows/uninstall_plastic.rb#L12) |

### PreviewUninstall

The code workflow `:code_preview_uninstall`, in [`preview_uninstall.rb:12`](../../../../scripts/lib/plastic/workflows/preview_uninstall.rb#L12).

On a dry run, lists each file and folder the uninstall would remove, the releases and the launcher among them when no agent stays registered, and the home it keeps.

![How PreviewUninstall runs: its steps, where it stops, and its outcomes](code_preview_uninstall.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| list the files the uninstall would remove | read |  | [`preview_uninstall.rb:15`](../../../../scripts/lib/plastic/workflows/preview_uninstall.rb#L15) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:done` | when `context.dry_run` | finishes, exit 0; next: %{original_command} | [`preview_uninstall.rb:26`](../../../../scripts/lib/plastic/workflows/preview_uninstall.rb#L26) |
| `:continue` | otherwise | runs [UninstallPlastic](#uninstallplastic) | [`preview_uninstall.rb:28`](../../../../scripts/lib/plastic/workflows/preview_uninstall.rb#L28) |

### UninstallPlastic

The code workflow `:code_uninstall_plastic`, in [`uninstall_plastic.rb:12`](../../../../scripts/lib/plastic/workflows/uninstall_plastic.rb#L12).

Removes the files Plastic registered with the chosen agents, then the releases and the launcher once no agent stays registered. The home with its stores stays.

![How UninstallPlastic runs: its steps, where it stops, and its outcomes](code_uninstall_plastic.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| remove the agent files | step | `context.removed` | [`uninstall_plastic.rb:17`](../../../../scripts/lib/plastic/workflows/uninstall_plastic.rb#L17) |
| remove the releases and the launcher | step | `context.releases_removed` | [`uninstall_plastic.rb:24`](../../../../scripts/lib/plastic/workflows/uninstall_plastic.rb#L24) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:done` | always | finishes, exit 0; next: plastic install | [`uninstall_plastic.rb:31`](../../../../scripts/lib/plastic/workflows/uninstall_plastic.rb#L31) |

It sets `removed`, `releases_removed`.

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| the preview changed no file | 0 | %{original_command} | [`preview_uninstall.rb:26`](../../../../scripts/lib/plastic/workflows/preview_uninstall.rb#L26) |
| Plastic is removed from the chosen agents; the home stays | 0 | plastic install | [`uninstall_plastic.rb:31`](../../../../scripts/lib/plastic/workflows/uninstall_plastic.rb#L31) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:97`](../../../../scripts/lib/plastic/code_workflow.rb#L97) |
