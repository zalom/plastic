# plastic intent unlink

Remove a link.

Removes one `links` row from ID to TARGET of the given kind.

```sh
plastic intent unlink ID KIND TARGET [--dry-run]
```

The command is `IntentUnlink`, in [`intent_unlink.rb:8`](../../../../scripts/lib/plastic/commands/intent_unlink.rb#L8). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ID` | the intent this link starts from | |
| `KIND` | cites, supersedes, answers, source or chain | |
| `TARGET` | the link's other end, as written when it was added | |
| `--dry-run` | preview the call in a disposable copy | `false` |

## What it touches

![What plastic intent unlink touches](component.svg)

## How the call flows

![The chain of workflows that plastic intent unlink runs](chain.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [RemoveLink](#removelink) | code | [`remove_link.rb:8`](../../../../scripts/lib/plastic/workflows/remove_link.rb#L8) |

### RemoveLink

The code workflow `:code_remove_link`, in [`remove_link.rb:8`](../../../../scripts/lib/plastic/workflows/remove_link.rb#L8).

Removes one link; fails when no such link exists.

![How RemoveLink runs: its steps, where it stops, and its outcomes](code_remove_link.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| forget a stop of an earlier call | read |  | [`code_workflow.rb:49`](../../../../scripts/lib/plastic/code_workflow.rb#L49) |
| remove the link | step | `!context.removed.nil?` | [`remove_link.rb:15`](../../../../scripts/lib/plastic/workflows/remove_link.rb#L15) |
| %{problem} | gate, stops with exit 1 | `context.problem.nil?` | [`remove_link.rb:21`](../../../../scripts/lib/plastic/workflows/remove_link.rb#L21) |
| say what was removed | read |  | [`remove_link.rb:23`](../../../../scripts/lib/plastic/workflows/remove_link.rb#L23) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:done` | always | finishes, exit 0; next: plastic sync down | [`remove_link.rb:27`](../../../../scripts/lib/plastic/workflows/remove_link.rb#L27) |

It sets `problem`, `removed`.

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| %{problem} | 1 | prints no next: line | [`remove_link.rb:21`](../../../../scripts/lib/plastic/workflows/remove_link.rb#L21) |
| the link is gone | 0 | plastic sync down | [`remove_link.rb:27`](../../../../scripts/lib/plastic/workflows/remove_link.rb#L27) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:97`](../../../../scripts/lib/plastic/code_workflow.rb#L97) |
