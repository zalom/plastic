# plastic graph ready

List the nodes ready to claim.

```sh
plastic graph ready ID
```

The command is `Graph::Ready`, in [`ready.rb:9`](../../../../lib/plastic/commands/graph/ready.rb#L9). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ID` | the intent | |

## What it touches

![What plastic graph ready touches](component.svg)

## How the call flows

![The chain of workflows that plastic graph ready runs](chain.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [Code::Graph::Ready](#codegraphready) | code | [`ready.rb:10`](../../../../lib/plastic/workflows/code/graph/ready.rb#L10) |

### Code::Graph::Ready

The code workflow `:code_ready_graph`, in [`ready.rb:10`](../../../../lib/plastic/workflows/code/graph/ready.rb#L10).

Lists the ready nodes of one intent's work graph.

![How Code::Graph::Ready runs: its steps, where it stops, and its outcomes](code_ready_graph.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| find the intent | read |  | [`ready.rb:15`](../../../../lib/plastic/workflows/code/graph/ready.rb#L15) |
| no intent %{intent_id} in this store | gate, stops with exit 1 | `!context.intent.nil?` | [`ready.rb:19`](../../../../lib/plastic/workflows/code/graph/ready.rb#L19) |
| list the ready nodes | read |  | [`ready.rb:21`](../../../../lib/plastic/workflows/code/graph/ready.rb#L21) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:nothing` | when `context.first.nil?` | finishes, exit 0; prints no next: line | [`ready.rb:27`](../../../../lib/plastic/workflows/code/graph/ready.rb#L27) |
| `:done` | otherwise | finishes, exit 0; next: plastic node claim %{intent_id} %{first} | [`ready.rb:28`](../../../../lib/plastic/workflows/code/graph/ready.rb#L28) |

It sets `intent`, `nodes`, `first`.

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| no intent %{intent_id} in this store | 1 | prints no next: line | [`ready.rb:19`](../../../../lib/plastic/workflows/code/graph/ready.rb#L19) |
| no node is ready to claim | 0 | prints no next: line | [`ready.rb:27`](../../../../lib/plastic/workflows/code/graph/ready.rb#L27) |
| node %{first} is ready | 0 | plastic node claim %{intent_id} %{first} | [`ready.rb:28`](../../../../lib/plastic/workflows/code/graph/ready.rb#L28) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |
