# plastic graph ready

List the nodes ready to claim.

```sh
plastic graph ready ID
```

The command is `Graph::Ready`, in [`ready.rb:9`](../../../../lib/plastic/commands/graph/ready.rb#L9). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ID` | the intent | |

## Components

![The components on the path of plastic graph ready](component.svg)

The figure shows the command, the workflows it runs, the classes behind them, and the databases and files they reach.

## The events of one call

The call starts the workflow `Code::Graph::Ready`, in [`ready.rb:10`](../../../../lib/plastic/workflows/code/graph/ready.rb#L10).

Lists the ready nodes of one intent's work graph.

![How Code::Graph::Ready runs: its steps, where it stops, and its outcomes](code_ready_graph.svg)

Its rows run in this order:

1. Read: find the intent. [`ready.rb:15`](../../../../lib/plastic/workflows/code/graph/ready.rb#L15)
2. Gate: passes when `!context.intent.nil?`; otherwise the call stops with exit 1 and prints no intent INTENT_ID in this store. [`ready.rb:19`](../../../../lib/plastic/workflows/code/graph/ready.rb#L19)
3. Read: list the ready nodes. [`ready.rb:21`](../../../../lib/plastic/workflows/code/graph/ready.rb#L21)
4. Outcome `:nothing`, when `context.first.nil?`: finishes with exit 0; prints no next: line. [`ready.rb:27`](../../../../lib/plastic/workflows/code/graph/ready.rb#L27)
5. Outcome `:done`, otherwise: finishes with exit 0; next: plastic node claim INTENT_ID FIRST. [`ready.rb:28`](../../../../lib/plastic/workflows/code/graph/ready.rb#L28)

It sets `intent`, `nodes`, `first`.

In the words of workflow engines, the rows are these four parts:

- **Trigger**: the call starts the workflow `Code::Graph::Ready`.
- **Activities**: 2 reads.
- **Transitions**: 1 gate stops the call when its check fails.
- **Outcomes**: `:nothing`, `:done` end the call.

## What one call reads, writes and prints

![What one call of plastic graph ready reads, writes and prints](touches.svg)

| Place | Database or file | Tables | Reads or writes | Code |
| --- | --- | --- | --- | --- |
| the store folder | work_graph.db | `edges`, `intents`, `nodes` | reads | [`ready.rb:11`](../../../../lib/plastic/commands/graph/ready.rb#L11) |

## How a call ends

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| no intent INTENT_ID in this store | 1 | prints no next: line | [`ready.rb:19`](../../../../lib/plastic/workflows/code/graph/ready.rb#L19) |
| no node is ready to claim | 0 | prints no next: line | [`ready.rb:27`](../../../../lib/plastic/workflows/code/graph/ready.rb#L27) |
| node FIRST is ready | 0 | plastic node claim INTENT_ID FIRST | [`ready.rb:28`](../../../../lib/plastic/workflows/code/graph/ready.rb#L28) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |

## What the page leaves out

Every call shares a few things that this page does not repeat; [the command DSL](../../dsl/README.md#what-every-call-shares) names them.

- No gate of this command refuses, so exit 3 never happens.
