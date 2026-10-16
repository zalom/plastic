# plastic intent archive

Archive an intent directory.

Takes a done, abandoned or future intent off the checkout; its rows stay.

```sh
plastic intent archive ID [--dry-run]
```

The command is `Intent::Archive`, in [`archive.rb:9`](../../../../lib/plastic/commands/intent/archive.rb#L9). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ID` | the intent to archive | |
| `--dry-run` | preview the call in a disposable copy | `false` |

## Components

![The components on the path of plastic intent archive](component.svg)

The figure shows the command, the workflows it runs, the classes behind them, and the databases and files they reach.

## The events of one call

The call starts the workflow `Code::Intent::Archive`, in [`archive.rb:10`](../../../../lib/plastic/workflows/code/intent/archive.rb#L10).

Takes a done, abandoned or future intent off the checkout. Its rows stay.

![How Code::Intent::Archive runs: its steps, where it stops, and its outcomes](code_archive_intent.svg)

Its rows run in this order:

1. Read: forget a stop of an earlier call. [`code_workflow.rb:54`](../../../../lib/plastic/code_workflow.rb#L54)
2. Step: archive the intent. Done when `!context.ok.nil? || !context.problem.nil?`, so a second call skips it. [`archive.rb:17`](../../../../lib/plastic/workflows/code/intent/archive.rb#L17)
3. Gate: passes when `context.kind != :unfinished`; otherwise the call stops with exit 1 and prints PROBLEM. [`archive.rb:24`](../../../../lib/plastic/workflows/code/intent/archive.rb#L24)
4. Gate: passes when `context.kind != :failure`; otherwise the call stops with exit 1 and prints PROBLEM. [`archive.rb:27`](../../../../lib/plastic/workflows/code/intent/archive.rb#L27)
5. Gate: passes when `context.kind != :refusal`; otherwise the call stops with exit 3 and prints PROBLEM. [`archive.rb:28`](../../../../lib/plastic/workflows/code/intent/archive.rb#L28)
6. Read: say it was archived. [`archive.rb:30`](../../../../lib/plastic/workflows/code/intent/archive.rb#L30)
7. Outcome `:done`, always: finishes with exit 0; next: plastic status. [`archive.rb:34`](../../../../lib/plastic/workflows/code/intent/archive.rb#L34)

It sets `problem`, `kind`, `ok`.

In the words of workflow engines, the rows are these four parts:

- **Trigger**: the call starts the workflow `Code::Intent::Archive`.
- **Activities**: 2 reads and 1 step.
- **Transitions**: 3 gates stop the call when their checks fail; a step runs only while its done check fails.
- **Outcomes**: `:done` ends the call.

## What one call reads, writes and prints

![What one call of plastic intent archive reads, writes and prints](touches.svg)

| Place | Database or file | Tables | Reads or writes | Code |
| --- | --- | --- | --- | --- |
| the store folder | knowledge_graph.db | `links` | reads and writes | [`archive.rb:12`](../../../../lib/plastic/commands/intent/archive.rb#L12) |
| the store folder | references.db | not found in the code | writes | [`archive.rb:12`](../../../../lib/plastic/commands/intent/archive.rb#L12) |
| the store folder | work_graph.db | `archives`, `intents` | reads and writes | [`archive.rb:12`](../../../../lib/plastic/commands/intent/archive.rb#L12) |
| the store folder | store/index.json | | writes | [`prints.rb:14`](../../../../lib/plastic/graph/prints.rb#L14) |

A second call runs the same rows again. A step runs again only when its done check fails.

| Step | Done when | The second call | Code |
| --- | --- | --- | --- |
| archive the intent | `!context.ok.nil? \|\| !context.problem.nil?` | skips it | [`archive.rb:17`](../../../../lib/plastic/workflows/code/intent/archive.rb#L17) |

## How a call ends

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| PROBLEM | 1 | plastic intent end INTENT_ID | [`archive.rb:24`](../../../../lib/plastic/workflows/code/intent/archive.rb#L24) |
| PROBLEM | 1 | prints no next: line | [`archive.rb:27`](../../../../lib/plastic/workflows/code/intent/archive.rb#L27) |
| PROBLEM | 3 | prints no next: line | [`archive.rb:28`](../../../../lib/plastic/workflows/code/intent/archive.rb#L28) |
| intent INTENT_ID is off the checkout | 0 | plastic status | [`archive.rb:34`](../../../../lib/plastic/workflows/code/intent/archive.rb#L34) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |

## What the page leaves out

Every call shares a few things that this page does not repeat; [the command DSL](../../dsl/README.md#what-every-call-shares) names them.

- A call that writes saves a routine run row in local.db. A stop by a gate or a step saves the run, and the next call resumes from it. A dry run saves no row.
