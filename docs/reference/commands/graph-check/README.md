# plastic graph check

Find a done node with no findings, an isolated node, a retry cap or no done criterion.

Runs the five findings of one intent's work graph and its spec.

```sh
plastic graph check ID
```

The command is `Graph::Check`, in [`check.rb:9`](../../../../lib/plastic/commands/graph/check.rb#L9). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ID` | the intent | |

## Components

![The components on the path of plastic graph check](component.svg)

The figure shows the command, the workflows it runs, the classes behind them, and the databases and files they reach.

## The events of one call

The call starts the workflow `Code::Graph::Check`, in [`check.rb:11`](../../../../lib/plastic/workflows/code/graph/check.rb#L11).

Prints each finding, or "no findings"; a finding fails the call.

![How Code::Graph::Check runs: its steps, where it stops, and its outcomes](code_check_graph.svg)

Its rows run in this order:

1. Read: find the intent. [`check.rb:16`](../../../../lib/plastic/workflows/code/graph/check.rb#L16)
2. Gate: passes when `!context.intent.nil?`; otherwise the call stops with exit 1 and prints no intent INTENT_ID in this store. [`check.rb:20`](../../../../lib/plastic/workflows/code/graph/check.rb#L20)
3. Read: find problems. [`check.rb:22`](../../../../lib/plastic/workflows/code/graph/check.rb#L22)
4. Gate: passes when `context.findings.empty?`; otherwise the call stops with exit 1 and prints see the findings above. [`check.rb:34`](../../../../lib/plastic/workflows/code/graph/check.rb#L34)
5. Read: find the first ready node. [`check.rb:36`](../../../../lib/plastic/workflows/code/graph/check.rb#L36)
6. Outcome `:nothing`, when `context.first.nil?`: finishes with exit 0; prints no next: line. [`check.rb:40`](../../../../lib/plastic/workflows/code/graph/check.rb#L40)
7. Outcome `:done`, otherwise: finishes with exit 0; next: plastic node claim INTENT_ID FIRST. [`check.rb:41`](../../../../lib/plastic/workflows/code/graph/check.rb#L41)

It sets `intent`, `findings`, `first`.

In the words of workflow engines, the rows are these four parts:

- **Trigger**: the call starts the workflow `Code::Graph::Check`.
- **Activities**: 3 reads.
- **Transitions**: 2 gates stop the call when their checks fail.
- **Outcomes**: `:nothing`, `:done` end the call.

## What one call reads, writes and prints

![What one call of plastic graph check reads, writes and prints](touches.svg)

| Place | Database or file | Tables | Reads or writes | Code |
| --- | --- | --- | --- | --- |
| the store folder | work_graph.db | `edges`, `intents`, `nodes` | reads | [`check.rb:11`](../../../../lib/plastic/commands/graph/check.rb#L11) |

## How a call ends

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| no intent INTENT_ID in this store | 1 | prints no next: line | [`check.rb:20`](../../../../lib/plastic/workflows/code/graph/check.rb#L20) |
| see the findings above | 1 | prints no next: line | [`check.rb:34`](../../../../lib/plastic/workflows/code/graph/check.rb#L34) |
| no node is ready to claim | 0 | prints no next: line | [`check.rb:40`](../../../../lib/plastic/workflows/code/graph/check.rb#L40) |
| node FIRST is ready | 0 | plastic node claim INTENT_ID FIRST | [`check.rb:41`](../../../../lib/plastic/workflows/code/graph/check.rb#L41) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |

## What the page leaves out

Every call shares a few things that this page does not repeat; [the command DSL](../../dsl/README.md#what-every-call-shares) names them.

- No gate of this command refuses, so exit 3 never happens.
