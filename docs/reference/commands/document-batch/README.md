# plastic document batch

Fetch qualified documents in request order.

```sh
plastic document batch REF...
```

The command is `Document::Batch`, in [`batch.rb:9`](../../../../lib/plastic/commands/document/batch.rb#L9). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `REF` | one or more plastic://STORE/INTENT/PATH?revision=SHA256 references | |

## What it touches

![What plastic document batch touches](component.svg)

## How the call flows

![The chain of workflows that plastic document batch runs](chain.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [Code::Document::Batch](#codedocumentbatch) | code | [`batch.rb:12`](../../../../lib/plastic/workflows/code/document/batch.rb#L12) |

### Code::Document::Batch

The code workflow `:code_batch_documents`, in [`batch.rb:12`](../../../../lib/plastic/workflows/code/document/batch.rb#L12).

Fetches qualified documents in the exact request order.

![How Code::Document::Batch runs: its steps, where it stops, and its outcomes](code_batch_documents.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| forget a stop of an earlier call | read |  | [`code_workflow.rb:54`](../../../../lib/plastic/code_workflow.rb#L54) |
| fetch the documents | read |  | [`batch.rb:19`](../../../../lib/plastic/workflows/code/document/batch.rb#L19) |
| %{problem} | gate, stops with exit 1 | `context.problem.nil?` | [`batch.rb:26`](../../../../lib/plastic/workflows/code/document/batch.rb#L26) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:done` | always | finishes, exit 0; prints no next: line | [`batch.rb:28`](../../../../lib/plastic/workflows/code/document/batch.rb#L28) |

It sets `problem`.

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| %{problem} | 1 | prints no next: line | [`batch.rb:26`](../../../../lib/plastic/workflows/code/document/batch.rb#L26) |
| the documents were read | 0 | prints no next: line | [`batch.rb:28`](../../../../lib/plastic/workflows/code/document/batch.rb#L28) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |
