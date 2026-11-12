# plastic intent unlink

Remove a link.

Removes one `links` row from ID to TARGET of the given kind.

```sh
plastic intent unlink ID KIND TARGET [--dry-run]
```

The command is `Intent::Unlink`, in [`unlink.rb:9`](../../../../lib/plastic/commands/intent/unlink.rb#L9). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

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
| [Code::Intent::Unlink](#codeintentunlink) | code | [`unlink.rb:10`](../../../../lib/plastic/workflows/code/intent/unlink.rb#L10) |

### Code::Intent::Unlink

The code workflow `:code_remove_link`, in [`unlink.rb:10`](../../../../lib/plastic/workflows/code/intent/unlink.rb#L10).

Removes one link; fails when no such link exists.

![How Code::Intent::Unlink runs: its steps, where it stops, and its outcomes](code_remove_link.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| forget a stop of an earlier call | read |  | [`code_workflow.rb:54`](../../../../lib/plastic/code_workflow.rb#L54) |
| remove the link | step | `!context.removed.nil?` | [`unlink.rb:17`](../../../../lib/plastic/workflows/code/intent/unlink.rb#L17) |
| %{problem} | gate, stops with exit 1 | `context.problem.nil?` | [`unlink.rb:23`](../../../../lib/plastic/workflows/code/intent/unlink.rb#L23) |
| say what was removed | read |  | [`unlink.rb:25`](../../../../lib/plastic/workflows/code/intent/unlink.rb#L25) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:done` | always | finishes, exit 0; next: plastic sync down | [`unlink.rb:29`](../../../../lib/plastic/workflows/code/intent/unlink.rb#L29) |

It sets `problem`, `removed`.

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| %{problem} | 1 | prints no next: line | [`unlink.rb:23`](../../../../lib/plastic/workflows/code/intent/unlink.rb#L23) |
| the link is gone | 0 | plastic sync down | [`unlink.rb:29`](../../../../lib/plastic/workflows/code/intent/unlink.rb#L29) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |
