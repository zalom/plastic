# plastic node done

Mark a claimed node done, with its findings as TEXT.

Moves a claimed node to done, with its findings. A done node takes new findings in place of the old.

```sh
plastic node done ID NODE TEXT
```

The command is `NodeDone`, in [`node_done.rb:8`](../../../../scripts/lib/plastic/commands/node_done.rb#L8). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ID` | the intent | |
| `NODE` | the node | |
| `TEXT` | what the work showed | |

## What it touches

![What plastic node done touches](component.svg)

## How the call flows

![The chain of workflows that plastic node done runs](chain.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [DoneNode](#donenode) | code | [`done_node.rb:8`](../../../../scripts/lib/plastic/workflows/done_node.rb#L8) |

### DoneNode

The code workflow `:code_done_node`, in [`done_node.rb:8`](../../../../scripts/lib/plastic/workflows/done_node.rb#L8).

Moves a claimed node to done, with its findings. A done node takes new findings in place of the old.

![How DoneNode runs: its steps, where it stops, and its outcomes](code_done_node.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| find the intent | read |  | [`move_node.rb:39`](../../../../scripts/lib/plastic/workflows/move_node.rb#L39) |
| no intent %{intent_id} in this store | gate, stops with exit 1 | `context.intent` | [`move_node.rb:40`](../../../../scripts/lib/plastic/workflows/move_node.rb#L40) |
| forget a refusal of an earlier call | read |  | [`move_node.rb:44`](../../../../scripts/lib/plastic/workflows/move_node.rb#L44) |
| finish the node | step | `[true, false].include?(context.moved)` | [`move_node.rb:45`](../../../../scripts/lib/plastic/workflows/move_node.rb#L45) |
| %{problem} | gate, stops with exit 1 | `context.moved == true` | [`move_node.rb:46`](../../../../scripts/lib/plastic/workflows/move_node.rb#L46) |
| say what was done | read |  | [`move_node.rb:59`](../../../../scripts/lib/plastic/workflows/move_node.rb#L59) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:done` | always | finishes, exit 0; next: plastic graph ready %{intent_id} | [`move_node.rb:60`](../../../../scripts/lib/plastic/workflows/move_node.rb#L60) |

It sets `intent`, `problem`, `moved`.

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| no intent %{intent_id} in this store | 1 | prints no next: line | [`move_node.rb:40`](../../../../scripts/lib/plastic/workflows/move_node.rb#L40) |
| %{problem} | 1 | prints no next: line | [`move_node.rb:46`](../../../../scripts/lib/plastic/workflows/move_node.rb#L46) |
| node %{id} is done | 0 | plastic graph ready %{intent_id} | [`move_node.rb:60`](../../../../scripts/lib/plastic/workflows/move_node.rb#L60) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:97`](../../../../scripts/lib/plastic/code_workflow.rb#L97) |
