# plastic graph show

Print every node and edge of an intent.

Prints one intent's nodes and edges from the rows. It reads and writes nothing.

```sh
plastic graph show ID
```

The command is `Graph::Show`, in [`show.rb:9`](../../../../lib/plastic/commands/graph/show.rb#L9). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ID` | the intent | |

## What it touches

![What plastic graph show touches](component.svg)

## How the call flows

![The chain of workflows that plastic graph show runs](chain.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [Code::Graph::Show](#codegraphshow) | code | [`show.rb:11`](../../../../lib/plastic/workflows/code/graph/show.rb#L11) |

### Code::Graph::Show

The code workflow `:code_show_graph`, in [`show.rb:11`](../../../../lib/plastic/workflows/code/graph/show.rb#L11).

Prints each node and edge from the rows. It never reads or writes graph.json.

![How Code::Graph::Show runs: its steps, where it stops, and its outcomes](code_show_graph.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| find the intent | read |  | [`show.rb:16`](../../../../lib/plastic/workflows/code/graph/show.rb#L16) |
| no intent %{intent_id} in this store | gate, stops with exit 1 | `!context.intent.nil?` | [`show.rb:20`](../../../../lib/plastic/workflows/code/graph/show.rb#L20) |
| print each node and edge | read |  | [`show.rb:22`](../../../../lib/plastic/workflows/code/graph/show.rb#L22) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:done` | always | finishes, exit 0; next: plastic graph ready %{intent_id} | [`show.rb:27`](../../../../lib/plastic/workflows/code/graph/show.rb#L27) |

It sets `intent`.

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| no intent %{intent_id} in this store | 1 | prints no next: line | [`show.rb:20`](../../../../lib/plastic/workflows/code/graph/show.rb#L20) |
| the rows hold this graph | 0 | plastic graph ready %{intent_id} | [`show.rb:27`](../../../../lib/plastic/workflows/code/graph/show.rb#L27) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |
