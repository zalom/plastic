# plastic intent unarchive

Restore an archived intent's directory exactly as it was archived.

```sh
plastic intent unarchive ID [--dry-run]
```

The command is `Intent::Unarchive`, in [`unarchive.rb:9`](../../../../lib/plastic/commands/intent/unarchive.rb#L9). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ID` | the archived intent to restore | |
| `--dry-run` | preview the call in a disposable copy | `false` |

## What it touches

![What plastic intent unarchive touches](component.svg)

## How the call flows

![The chain of workflows that plastic intent unarchive runs](chain.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [Code::Intent::Unarchive](#codeintentunarchive) | code | [`unarchive.rb:10`](../../../../lib/plastic/workflows/code/intent/unarchive.rb#L10) |

### Code::Intent::Unarchive

The code workflow `:code_unarchive_intent`, in [`unarchive.rb:10`](../../../../lib/plastic/workflows/code/intent/unarchive.rb#L10).

Restores the archived directory snapshot, including bytes and metadata.

![How Code::Intent::Unarchive runs: its steps, where it stops, and its outcomes](code_unarchive_intent.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| forget a stop of an earlier call | read |  | [`code_workflow.rb:54`](../../../../lib/plastic/code_workflow.rb#L54) |
| restore the intent | step | `!context.ok.nil? \|\| !context.problem.nil?` | [`unarchive.rb:17`](../../../../lib/plastic/workflows/code/intent/unarchive.rb#L17) |
| %{problem} | gate, stops with exit 1 | `context.problem.nil?` | [`unarchive.rb:23`](../../../../lib/plastic/workflows/code/intent/unarchive.rb#L23) |
| say it was restored | read |  | [`unarchive.rb:25`](../../../../lib/plastic/workflows/code/intent/unarchive.rb#L25) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:done` | always | finishes, exit 0; next: plastic intent show %{intent_id} | [`unarchive.rb:29`](../../../../lib/plastic/workflows/code/intent/unarchive.rb#L29) |

It sets `problem`, `ok`.

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| %{problem} | 1 | prints no next: line | [`unarchive.rb:23`](../../../../lib/plastic/workflows/code/intent/unarchive.rb#L23) |
| intent %{intent_id} is back on the checkout | 0 | plastic intent show %{intent_id} | [`unarchive.rb:29`](../../../../lib/plastic/workflows/code/intent/unarchive.rb#L29) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |
