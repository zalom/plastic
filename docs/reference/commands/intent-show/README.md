# plastic intent show

Print one intent's status, criteria, decisions, rulings and nodes.

```sh
plastic intent show ID
```

The command is `Intent::Show`, in [`show.rb:10`](../../../../lib/plastic/commands/intent/show.rb#L10). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ID` | the intent | |

## What it touches

![What plastic intent show touches](component.svg)

## How the call flows

![The chain of workflows that plastic intent show runs](chain.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [Code::Intent::Show](#codeintentshow) | code | [`show.rb:13`](../../../../lib/plastic/workflows/code/intent/show.rb#L13) |

### Code::Intent::Show

The code workflow `:code_show_intent`, in [`show.rb:13`](../../../../lib/plastic/workflows/code/intent/show.rb#L13).

Prints one intent's status, criteria count, open decisions, rulings, nodes and last savepoint lines; refuses an unknown id.

![How Code::Intent::Show runs: its steps, where it stops, and its outcomes](code_show_intent.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| find the intent | read |  | [`show.rb:18`](../../../../lib/plastic/workflows/code/intent/show.rb#L18) |
| no intent %{intent_id} in this store | gate, stops with exit 1 | `!context.intent.nil?` | [`show.rb:22`](../../../../lib/plastic/workflows/code/intent/show.rb#L22) |
| print the intent | read |  | [`show.rb:24`](../../../../lib/plastic/workflows/code/intent/show.rb#L24) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:done` | always | finishes, exit 0; next: plastic intent brief %{intent_id} | [`show.rb:50`](../../../../lib/plastic/workflows/code/intent/show.rb#L50) |

It sets `intent`.

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| no intent %{intent_id} in this store | 1 | prints no next: line | [`show.rb:22`](../../../../lib/plastic/workflows/code/intent/show.rb#L22) |
| intent %{intent_id} is shown | 0 | plastic intent brief %{intent_id} | [`show.rb:50`](../../../../lib/plastic/workflows/code/intent/show.rb#L50) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |
