# plastic node add

Add a node to an intent's work graph.

```sh
plastic node add ID TITLE --criterion KEY [--input PATH]
```

The command is `Node::Add`, in [`add.rb:9`](../../../../lib/plastic/commands/node/add.rb#L9). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ID` | the intent | |
| `TITLE` | what the node is for | |
| `--criterion KEY` | the key of the spec done criterion this node serves |  |
| `--input PATH` | a file the node reads |  |

## What it touches

![What plastic node add touches](component.svg)

## How the call flows

![The chain of workflows that plastic node add runs](chain.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [Code::Node::Add](#codenodeadd) | code | [`add.rb:12`](../../../../lib/plastic/workflows/code/node/add.rb#L12) |

### Code::Node::Add

The code workflow `:code_add_node`, in [`add.rb:12`](../../../../lib/plastic/workflows/code/node/add.rb#L12).

Writes a new node, open and ready, unless the intent is done or abandoned.

![How Code::Node::Add runs: its steps, where it stops, and its outcomes](code_add_node.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| check the intent | read |  | [`add.rb:17`](../../../../lib/plastic/workflows/code/node/add.rb#L17) |
| %{problem} | gate, stops with exit 1 | `context.problem.nil?` | [`add.rb:21`](../../../../lib/plastic/workflows/code/node/add.rb#L21) |
| add the node | step | `!context.id.nil?` | [`add.rb:23`](../../../../lib/plastic/workflows/code/node/add.rb#L23) |
| say what was added | read |  | [`add.rb:29`](../../../../lib/plastic/workflows/code/node/add.rb#L29) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:done` | always | finishes, exit 0; next: plastic node claim %{intent_id} %{id} | [`add.rb:45`](../../../../lib/plastic/workflows/code/node/add.rb#L45) |

It sets `problem`, `id`.

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| %{problem} | 1 | prints no next: line | [`add.rb:21`](../../../../lib/plastic/workflows/code/node/add.rb#L21) |
| node %{id} is open | 0 | plastic node claim %{intent_id} %{id} | [`add.rb:45`](../../../../lib/plastic/workflows/code/node/add.rb#L45) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |
