# plastic intent show

Print one intent's status, criteria, decisions, rulings and nodes.

```sh
plastic intent show ID
```

The command is `Intent::Show`, in [`show.rb:10`](../../../../lib/plastic/commands/intent/show.rb#L10). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ID` | the intent | |

## Components

![The components on the path of plastic intent show](component.svg)

The figure shows the command, the workflows it runs, the classes behind them, and the databases and files they reach.

## The events of one call

The call starts the workflow `Code::Intent::Show`, in [`show.rb:13`](../../../../lib/plastic/workflows/code/intent/show.rb#L13).

Prints one intent's status, criteria count, open decisions, rulings, nodes and last savepoint lines; refuses an unknown id.

![How Code::Intent::Show runs: its steps, where it stops, and its outcomes](code_show_intent.svg)

Its rows run in this order:

1. Read: find the intent. [`show.rb:18`](../../../../lib/plastic/workflows/code/intent/show.rb#L18)
2. Gate: passes when `!context.intent.nil?`; otherwise the call stops with exit 1 and prints no intent INTENT_ID in this store. [`show.rb:22`](../../../../lib/plastic/workflows/code/intent/show.rb#L22)
3. Read: print the intent. [`show.rb:24`](../../../../lib/plastic/workflows/code/intent/show.rb#L24)
4. Outcome `:done`, always: finishes with exit 0; next: plastic intent brief INTENT_ID. [`show.rb:50`](../../../../lib/plastic/workflows/code/intent/show.rb#L50)

It sets `intent`.

In the words of workflow engines, the rows are these four parts:

- **Trigger**: the call starts the workflow `Code::Intent::Show`.
- **Activities**: 2 reads.
- **Transitions**: 1 gate stops the call when its check fails.
- **Outcomes**: `:done` end the call.

## What one call reads, writes and prints

![What one call of plastic intent show reads, writes and prints](touches.svg)

| Place | Database or file | Tables | Reads or writes | Code |
| --- | --- | --- | --- | --- |
| the store folder | knowledge_graph.db | `documents`, `rulings` | reads | [`show.rb:12`](../../../../lib/plastic/commands/intent/show.rb#L12) |
| the store folder | work_graph.db | `intents`, `nodes`, `savepoints` | reads | [`show.rb:12`](../../../../lib/plastic/commands/intent/show.rb#L12) |

## How a call ends

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| no intent INTENT_ID in this store | 1 | prints no next: line | [`show.rb:22`](../../../../lib/plastic/workflows/code/intent/show.rb#L22) |
| intent INTENT_ID is shown | 0 | plastic intent brief INTENT_ID | [`show.rb:50`](../../../../lib/plastic/workflows/code/intent/show.rb#L50) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |

## What the page leaves out

Every call shares a few things that this page does not repeat; [the command DSL](../../dsl/README.md#what-every-call-shares) names them.

- No gate of this command refuses, so exit 3 never happens.
