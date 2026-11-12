# plastic edge remove

Remove an edge.

Removes one edge. Fails when no such edge exists.

```sh
plastic edge remove ID FROM TO [--dry-run]
```

The command is `Edge::Remove`, in [`remove.rb:9`](../../../../lib/plastic/commands/edge/remove.rb#L9). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ID` | the intent | |
| `FROM` | the edge's start | |
| `TO` | the edge's end | |
| `--dry-run` | preview the call in a disposable copy | `false` |

## What it touches

![What plastic edge remove touches](component.svg)

## How the call flows

![The chain of workflows that plastic edge remove runs](chain.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [Code::Edge::Remove](#codeedgeremove) | code | [`remove.rb:10`](../../../../lib/plastic/workflows/code/edge/remove.rb#L10) |

### Code::Edge::Remove

The code workflow `:code_remove_edge`, in [`remove.rb:10`](../../../../lib/plastic/workflows/code/edge/remove.rb#L10).

Removes one edge; fails when no such edge exists.

![How Code::Edge::Remove runs: its steps, where it stops, and its outcomes](code_remove_edge.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| forget a refusal of an earlier call | read |  | [`remove.rb:15`](../../../../lib/plastic/workflows/code/edge/remove.rb#L15) |
| remove the edge | step | `!context.removed.nil?` | [`remove.rb:17`](../../../../lib/plastic/workflows/code/edge/remove.rb#L17) |
| %{problem} | gate, stops with exit 1 | `context.problem.nil?` | [`remove.rb:23`](../../../../lib/plastic/workflows/code/edge/remove.rb#L23) |
| say what was removed | read |  | [`remove.rb:25`](../../../../lib/plastic/workflows/code/edge/remove.rb#L25) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:done` | always | finishes, exit 0; next: plastic graph show %{intent_id} | [`remove.rb:29`](../../../../lib/plastic/workflows/code/edge/remove.rb#L29) |

It sets `problem`, `removed`.

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| %{problem} | 1 | prints no next: line | [`remove.rb:23`](../../../../lib/plastic/workflows/code/edge/remove.rb#L23) |
| edge %{from} to %{to} is gone | 0 | plastic graph show %{intent_id} | [`remove.rb:29`](../../../../lib/plastic/workflows/code/edge/remove.rb#L29) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |
