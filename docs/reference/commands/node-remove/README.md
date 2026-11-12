# plastic node remove

Remove a node; its edges stay as rows.

Moves a node from open to removed. Its edges stay, but a removed node never counts as ready or isolated.

```sh
plastic node remove ID NODE [--reason TEXT] [--dry-run]
```

The command is `Node::Remove`, in [`remove.rb:10`](../../../../lib/plastic/commands/node/remove.rb#L10). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ID` | the intent | |
| `NODE` | the node | |
| `--reason TEXT` | why the node is removed |  |
| `--dry-run` | preview the call in a disposable copy | `false` |

## What it touches

![What plastic node remove touches](component.svg)

## How the call flows

![The chain of workflows that plastic node remove runs](chain.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [RemoveNode](#removenode) | code | [`remove_node.rb:8`](../../../../lib/plastic/workflows/remove_node.rb#L8) |

### RemoveNode

The code workflow `:code_remove_node`, in [`remove_node.rb:8`](../../../../lib/plastic/workflows/remove_node.rb#L8).

Moves a node from open to removed.

![How RemoveNode runs: its steps, where it stops, and its outcomes](code_remove_node.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| find the intent | read |  | [`move_node.rb:39`](../../../../lib/plastic/workflows/move_node.rb#L39) |
| no intent %{intent_id} in this store | gate, stops with exit 1 | `context.intent` | [`move_node.rb:40`](../../../../lib/plastic/workflows/move_node.rb#L40) |
| forget a refusal of an earlier call | read |  | [`move_node.rb:44`](../../../../lib/plastic/workflows/move_node.rb#L44) |
| remove the node | step | `[true, false].include?(context.moved)` | [`move_node.rb:45`](../../../../lib/plastic/workflows/move_node.rb#L45) |
| %{problem} | gate, stops with exit 1 | `context.moved == true` | [`move_node.rb:46`](../../../../lib/plastic/workflows/move_node.rb#L46) |
| say what was removed | read |  | [`move_node.rb:59`](../../../../lib/plastic/workflows/move_node.rb#L59) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:done` | always | finishes, exit 0; next: plastic graph ready %{intent_id} | [`move_node.rb:60`](../../../../lib/plastic/workflows/move_node.rb#L60) |

It sets `intent`, `problem`, `moved`.

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| no intent %{intent_id} in this store | 1 | prints no next: line | [`move_node.rb:40`](../../../../lib/plastic/workflows/move_node.rb#L40) |
| %{problem} | 1 | prints no next: line | [`move_node.rb:46`](../../../../lib/plastic/workflows/move_node.rb#L46) |
| node %{id} is removed | 0 | plastic graph ready %{intent_id} | [`move_node.rb:60`](../../../../lib/plastic/workflows/move_node.rb#L60) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |
