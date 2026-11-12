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

## What it touches

![What plastic document get touches](component.svg)

## How the call flows

![The chain of workflows that plastic document get runs](chain.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [Code::Document::Get](#codedocumentget) | code | [`get.rb:12`](../../../../lib/plastic/workflows/code/document/get.rb#L12) |

### Code::Document::Get

The code workflow `:code_get_document`, in [`get.rb:12`](../../../../lib/plastic/workflows/code/document/get.rb#L12).

Fetches one current or immutable document, or one bounded passage of it.

![How Code::Document::Get runs: its steps, where it stops, and its outcomes](code_get_document.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| forget a stop of an earlier call | read |  | [`code_workflow.rb:54`](../../../../lib/plastic/code_workflow.rb#L54) |
| fetch the document | read |  | [`get.rb:19`](../../../../lib/plastic/workflows/code/document/get.rb#L19) |
| %{problem} | gate, stops with exit 1 | `context.problem.nil?` | [`get.rb:25`](../../../../lib/plastic/workflows/code/document/get.rb#L25) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:done` | always | finishes, exit 0; prints no next: line | [`get.rb:27`](../../../../lib/plastic/workflows/code/document/get.rb#L27) |

It sets `problem`.

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| %{problem} | 1 | prints no next: line | [`get.rb:25`](../../../../lib/plastic/workflows/code/document/get.rb#L25) |
| the document was read | 0 | prints no next: line | [`get.rb:27`](../../../../lib/plastic/workflows/code/document/get.rb#L27) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |
