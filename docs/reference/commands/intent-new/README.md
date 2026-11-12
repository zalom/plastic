# plastic intent new

Open an intent: write its rows and its folder.

Opens an intent: writes its row and its first rows, and prints its folder and store/index.json in the same call.

```sh
plastic intent new TITLE... [--parent ID] [--ref REF] [--after ID] [--kind KIND] [--status STATUS]
```

The command is `Intent::New`, in [`new.rb:10`](../../../../lib/plastic/commands/intent/new.rb#L10). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `TITLE` | what the intent is for, in words | |
| `--parent ID` | the intent this one is a child of |  |
| `--ref REF` | a ticket, a link, or another intent as ID-ORIGIN |  |
| `--after ID` | an intent this one grows out of, linked as source |  |
| `--kind KIND` | the kind of work | `"work"` |
| `--status STATUS` | open, active, parked or future | `"open"` |

## What it touches

![What plastic intent new touches](component.svg)

## How the call flows

![The chain of workflows that plastic intent new runs](chain.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [Code::Intent::New](#codeintentnew) | code | [`new.rb:10`](../../../../lib/plastic/workflows/code/intent/new.rb#L10) |

### Code::Intent::New

The code workflow `:code_write_intent`, in [`new.rb:10`](../../../../lib/plastic/workflows/code/intent/new.rb#L10).

Writes a new intent's rows; the command prints its folder and store/index.json.

![How Code::Intent::New runs: its steps, where it stops, and its outcomes](code_write_intent.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| check the call | read |  | [`new.rb:16`](../../../../lib/plastic/workflows/code/intent/new.rb#L16) |
| %{problem} | gate, stops with exit 1 | `context.problem.nil?` | [`new.rb:21`](../../../../lib/plastic/workflows/code/intent/new.rb#L21) |
| write the intent | step | `!context.intent_id.nil?` | [`new.rb:23`](../../../../lib/plastic/workflows/code/intent/new.rb#L23) |
| link to what it grows out of | step | `context.after.nil? \|\| !context.linked.nil?` | [`new.rb:29`](../../../../lib/plastic/workflows/code/intent/new.rb#L29) |
| say what was written | read |  | [`new.rb:34`](../../../../lib/plastic/workflows/code/intent/new.rb#L34) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:done` | always | finishes, exit 0; next: plastic next | [`new.rb:39`](../../../../lib/plastic/workflows/code/intent/new.rb#L39) |

It sets `problem`, `intent_id`, `linked`.

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| %{problem} | 1 | prints no next: line | [`new.rb:21`](../../../../lib/plastic/workflows/code/intent/new.rb#L21) |
| intent %{intent_id} has its rows and its files | 0 | plastic next | [`new.rb:39`](../../../../lib/plastic/workflows/code/intent/new.rb#L39) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |
