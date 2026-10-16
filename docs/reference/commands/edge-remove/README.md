# plastic edge remove

Remove an edge.

Removes one edge. Fails when no such edge exists.

```sh
plastic edge remove ID FROM TO [--dry-run]
```

The command is `Edge::Remove`, in [`remove.rb:9`](../../../../lib/plastic/commands/edge/remove.rb#L9). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ID` | the intent | |
| `FROM` | the edge's start | |
| `TO` | the edge's end | |
| `--dry-run` | preview the call in a disposable copy | `false` |

## Components

![The components on the path of plastic edge remove](component.svg)

The figure shows the command, the workflows it runs, the classes behind them, and the databases and files they reach.

## The events of one call

The call starts the workflow `Code::Edge::Remove`, in [`remove.rb:10`](../../../../lib/plastic/workflows/code/edge/remove.rb#L10).

Removes one edge; fails when no such edge exists.

![How Code::Edge::Remove runs: its steps, where it stops, and its outcomes](code_remove_edge.svg)

Its rows run in this order:

1. Read: forget a refusal of an earlier call. [`remove.rb:15`](../../../../lib/plastic/workflows/code/edge/remove.rb#L15)
2. Step: remove the edge. Done when `!context.removed.nil?`, so a second call skips it. [`remove.rb:17`](../../../../lib/plastic/workflows/code/edge/remove.rb#L17)
3. Gate: passes when `context.problem.nil?`; otherwise the call stops with exit 1 and prints PROBLEM. [`remove.rb:23`](../../../../lib/plastic/workflows/code/edge/remove.rb#L23)
4. Read: say what was removed. [`remove.rb:25`](../../../../lib/plastic/workflows/code/edge/remove.rb#L25)
5. Outcome `:done`, always: finishes with exit 0; next: plastic graph show INTENT_ID. [`remove.rb:29`](../../../../lib/plastic/workflows/code/edge/remove.rb#L29)

It sets `problem`, `removed`.

In the words of workflow engines, the rows are these four parts:

- **Trigger**: the call starts the workflow `Code::Edge::Remove`.
- **Activities**: 2 reads and 1 step.
- **Transitions**: 1 gate stops the call when its check fails; a step runs only while its done check fails.
- **Outcomes**: `:done` ends the call.

## What one call reads, writes and prints

![What one call of plastic edge remove reads, writes and prints](touches.svg)

| Place | Database or file | Tables | Reads or writes | Code |
| --- | --- | --- | --- | --- |
| the store folder | work_graph.db | `edges` | writes | [`remove.rb:13`](../../../../lib/plastic/commands/edge/remove.rb#L13) |
| the store folder | store/index.json | | writes | [`prints.rb:14`](../../../../lib/plastic/graph/prints.rb#L14) |
| the store folder | store/ID--SLUG/PATH | | writes | [`prints.rb:15`](../../../../lib/plastic/graph/prints.rb#L15) |
| the store folder | store/ID--SLUG/savepoint.md | | writes | [`prints.rb:16`](../../../../lib/plastic/graph/prints.rb#L16) |
| the store folder | store/ID--SLUG/graph.json | | writes | [`prints.rb:17`](../../../../lib/plastic/graph/prints.rb#L17) |
| the store folder | store/ID--SLUG/context.json | | writes | [`prints.rb:18`](../../../../lib/plastic/graph/prints.rb#L18) |

A second call runs the same rows again. A step runs again only when its done check fails.

| Step | Done when | The second call | Code |
| --- | --- | --- | --- |
| remove the edge | `!context.removed.nil?` | skips it | [`remove.rb:17`](../../../../lib/plastic/workflows/code/edge/remove.rb#L17) |

## How a call ends

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| PROBLEM | 1 | prints no next: line | [`remove.rb:23`](../../../../lib/plastic/workflows/code/edge/remove.rb#L23) |
| edge FROM to TO is gone | 0 | plastic graph show INTENT_ID | [`remove.rb:29`](../../../../lib/plastic/workflows/code/edge/remove.rb#L29) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |

## What the page leaves out

Every call shares a few things that this page does not repeat; [the command DSL](../../dsl/README.md#what-every-call-shares) names them.

- A call that writes saves a routine run row in local.db. A stop by a gate or a step saves the run, and the next call resumes from it. A dry run saves no row.
