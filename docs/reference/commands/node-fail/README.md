# plastic node fail

Mark a claimed node failed, with the reason as TEXT.

```sh
plastic node fail ID NODE TEXT
```

The command is `NodeFail`, in [`node_fail.rb:8`](../../../../scripts/lib/plastic/commands/node_fail.rb#L8). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ID` | the intent | |
| `NODE` | the node | |
| `TEXT` | why it failed | |

## What it touches

![What plastic node fail touches](component.svg)

## How the call flows

![The chain of workflows that plastic node fail runs](chain.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [FailNode](#failnode) | code | [`fail_node.rb:8`](../../../../scripts/lib/plastic/workflows/fail_node.rb#L8) |

### FailNode

The code workflow `:code_fail_node`, in [`fail_node.rb:8`](../../../../scripts/lib/plastic/workflows/fail_node.rb#L8).

Moves a claimed node to failed, with a reason.

![How FailNode runs: its steps, where it stops, and its outcomes](code_fail_node.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| find the intent | read |  | [`move_node.rb:39`](../../../../scripts/lib/plastic/workflows/move_node.rb#L39) |
| no intent %{intent_id} in this store | gate, stops with exit 1 | `context.intent` | [`move_node.rb:40`](../../../../scripts/lib/plastic/workflows/move_node.rb#L40) |
| forget a refusal of an earlier call | read |  | [`move_node.rb:44`](../../../../scripts/lib/plastic/workflows/move_node.rb#L44) |
| fail the node | step | `[true, false].include?(context.moved)` | [`move_node.rb:45`](../../../../scripts/lib/plastic/workflows/move_node.rb#L45) |
| %{problem} | gate, stops with exit 1 | `context.moved == true` | [`move_node.rb:46`](../../../../scripts/lib/plastic/workflows/move_node.rb#L46) |
| say what failed | read |  | [`move_node.rb:59`](../../../../scripts/lib/plastic/workflows/move_node.rb#L59) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:done` | always | finishes, exit 0; next: plastic node release %{intent_id} %{id} | [`move_node.rb:60`](../../../../scripts/lib/plastic/workflows/move_node.rb#L60) |

It sets `intent`, `problem`, `moved`.

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| no intent %{intent_id} in this store | 1 | prints no next: line | [`move_node.rb:40`](../../../../scripts/lib/plastic/workflows/move_node.rb#L40) |
| %{problem} | 1 | prints no next: line | [`move_node.rb:46`](../../../../scripts/lib/plastic/workflows/move_node.rb#L46) |
| node %{id} is failed | 0 | plastic node release %{intent_id} %{id} | [`move_node.rb:60`](../../../../scripts/lib/plastic/workflows/move_node.rb#L60) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:97`](../../../../scripts/lib/plastic/code_workflow.rb#L97) |
