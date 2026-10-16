# plastic document get

Fetch one current or revision-qualified document.

Fetches one current or immutable document by its qualified reference.

```sh
plastic document get REF [--passage N]
```

The command is `Document::Get`, in [`get.rb:9`](../../../../lib/plastic/commands/document/get.rb#L9). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `REF` | plastic://STORE/INTENT/PATH?revision=SHA256 | |
| `--passage N` | one-based bounded passage position |  |

## Components

![The components on the path of plastic document get](component.svg)

The figure shows the command, the workflows it runs, the classes behind them, and the databases and files they reach.

## The events of one call

The call starts the workflow `Code::Document::Get`, in [`get.rb:12`](../../../../lib/plastic/workflows/code/document/get.rb#L12).

Fetches one current or immutable document, or one bounded passage of it.

![How Code::Document::Get runs: its steps, where it stops, and its outcomes](code_get_document.svg)

Its rows run in this order:

1. Read: forget a stop of an earlier call. [`code_workflow.rb:54`](../../../../lib/plastic/code_workflow.rb#L54)
2. Read: fetch the document. [`get.rb:19`](../../../../lib/plastic/workflows/code/document/get.rb#L19)
3. Gate: passes when `context.problem.nil?`; otherwise the call stops with exit 1 and prints PROBLEM. [`get.rb:25`](../../../../lib/plastic/workflows/code/document/get.rb#L25)
4. Outcome `:done`, always: finishes with exit 0; prints no next: line. [`get.rb:27`](../../../../lib/plastic/workflows/code/document/get.rb#L27)

It sets `problem`.

In the words of workflow engines, the rows are these four parts:

- **Trigger**: the call starts the workflow `Code::Document::Get`.
- **Activities**: 2 reads.
- **Transitions**: 1 gate stops the call when its check fails.
- **Outcomes**: `:done` end the call.

## What one call reads, writes and prints

![What one call of plastic document get reads, writes and prints](touches.svg)

| Place | Database or file | Tables | Reads or writes | Code |
| --- | --- | --- | --- | --- |
| the store folder | knowledge_graph.db | not found in the code | reads | [`get.rb:12`](../../../../lib/plastic/commands/document/get.rb#L12) |

## How a call ends

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| PROBLEM | 1 | prints no next: line | [`get.rb:25`](../../../../lib/plastic/workflows/code/document/get.rb#L25) |
| the document was read | 0 | prints no next: line | [`get.rb:27`](../../../../lib/plastic/workflows/code/document/get.rb#L27) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |

## What the page leaves out

Every call shares a few things that this page does not repeat; [the command DSL](../../dsl/README.md#what-every-call-shares) names them.

- No gate of this command refuses, so exit 3 never happens.
