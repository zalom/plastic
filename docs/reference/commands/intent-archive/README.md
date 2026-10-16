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

## What it touches

![What plastic intent archive touches](component.svg)

## How the call flows

![The chain of workflows that plastic intent archive runs](chain.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [Code::Intent::Archive](#codeintentarchive) | code | [`archive.rb:10`](../../../../lib/plastic/workflows/code/intent/archive.rb#L10) |

### Code::Intent::Archive

The code workflow `:code_archive_intent`, in [`archive.rb:10`](../../../../lib/plastic/workflows/code/intent/archive.rb#L10).

Takes a done, abandoned or future intent off the checkout. Its rows stay.

![How Code::Intent::Archive runs: its steps, where it stops, and its outcomes](code_archive_intent.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| forget a stop of an earlier call | read |  | [`code_workflow.rb:54`](../../../../lib/plastic/code_workflow.rb#L54) |
| archive the intent | step | `!context.ok.nil? \|\| !context.problem.nil?` | [`archive.rb:17`](../../../../lib/plastic/workflows/code/intent/archive.rb#L17) |
| %{problem} | gate, stops with exit 1 | `context.kind != :unfinished` | [`archive.rb:24`](../../../../lib/plastic/workflows/code/intent/archive.rb#L24) |
| %{problem} | gate, stops with exit 1 | `context.kind != :failure` | [`archive.rb:27`](../../../../lib/plastic/workflows/code/intent/archive.rb#L27) |
| %{problem} | gate, stops with exit 3 | `context.kind != :refusal` | [`archive.rb:28`](../../../../lib/plastic/workflows/code/intent/archive.rb#L28) |
| say it was archived | read |  | [`archive.rb:30`](../../../../lib/plastic/workflows/code/intent/archive.rb#L30) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:done` | always | finishes, exit 0; next: plastic status | [`archive.rb:34`](../../../../lib/plastic/workflows/code/intent/archive.rb#L34) |

It sets `problem`, `kind`, `ok`.

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| %{problem} | 1 | plastic intent end %{intent_id} | [`archive.rb:24`](../../../../lib/plastic/workflows/code/intent/archive.rb#L24) |
| %{problem} | 1 | prints no next: line | [`archive.rb:27`](../../../../lib/plastic/workflows/code/intent/archive.rb#L27) |
| %{problem} | 3 | prints no next: line | [`archive.rb:28`](../../../../lib/plastic/workflows/code/intent/archive.rb#L28) |
| intent %{intent_id} is off the checkout | 0 | plastic status | [`archive.rb:34`](../../../../lib/plastic/workflows/code/intent/archive.rb#L34) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |
