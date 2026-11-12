# plastic edge add

Add a needs edge between two nodes.

Adds a needs edge between two nodes of the same intent, guarded against a self edge, a missing or removed node, and a loop.

```sh
plastic edge add ID FROM TO
```

The command is `Edge::Add`, in [`add.rb:10`](../../../../lib/plastic/commands/edge/add.rb#L10). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ID` | the intent | |
| `FROM` | the node that must be done first | |
| `TO` | the node that waits on it | |

## What it touches

![What plastic edge add touches](component.svg)

## How the call flows

![The chain of workflows that plastic edge add runs](chain.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [Code::Edge::Add](#codeedgeadd) | code | [`add.rb:11`](../../../../lib/plastic/workflows/code/edge/add.rb#L11) |

### Code::Edge::Add

The code workflow `:code_add_edge`, in [`add.rb:11`](../../../../lib/plastic/workflows/code/edge/add.rb#L11).

Writes one guarded edge: fails on a self edge, a missing or removed node, or a loop back to its own start.

![How Code::Edge::Add runs: its steps, where it stops, and its outcomes](code_add_edge.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| find the intent | read |  | [`add.rb:16`](../../../../lib/plastic/workflows/code/edge/add.rb#L16) |
| no intent %{intent_id} in this store | gate, stops with exit 1 | `!context.intent.nil?` | [`add.rb:20`](../../../../lib/plastic/workflows/code/edge/add.rb#L20) |
| forget a refusal of an earlier call | read |  | [`add.rb:22`](../../../../lib/plastic/workflows/code/edge/add.rb#L22) |
| add the edge | step | `!context.added.nil?` | [`add.rb:24`](../../../../lib/plastic/workflows/code/edge/add.rb#L24) |
| %{problem} | gate, stops with exit 1 | `context.problem.nil?` | [`add.rb:30`](../../../../lib/plastic/workflows/code/edge/add.rb#L30) |
| say what was added | read |  | [`add.rb:32`](../../../../lib/plastic/workflows/code/edge/add.rb#L32) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:done` | always | finishes, exit 0; next: plastic graph show %{intent_id} | [`add.rb:36`](../../../../lib/plastic/workflows/code/edge/add.rb#L36) |

It sets `intent`, `problem`, `added`.

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| no intent %{intent_id} in this store | 1 | prints no next: line | [`add.rb:20`](../../../../lib/plastic/workflows/code/edge/add.rb#L20) |
| %{problem} | 1 | prints no next: line | [`add.rb:30`](../../../../lib/plastic/workflows/code/edge/add.rb#L30) |
| edge %{from} to %{to} is written | 0 | plastic graph show %{intent_id} | [`add.rb:36`](../../../../lib/plastic/workflows/code/edge/add.rb#L36) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |
