# plastic intent rule

Write an owner ruling, with --supersedes to replace an older one.

Writes one owner ruling against an intent, numbered in order, one after the last. --supersedes names an older ruling and links the two.

```sh
plastic intent rule ID TEXT [--supersedes RULING_ID]
```

The command is `Intent::Rule`, in [`rule.rb:10`](../../../../lib/plastic/commands/intent/rule.rb#L10). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ID` | the intent | |
| `TEXT` | the ruling, in the owner's words | |
| `--supersedes RULING_ID` | an older ruling this one replaces |  |

## What it touches

![What plastic intent rule touches](component.svg)

## How the call flows

![The chain of workflows that plastic intent rule runs](chain.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [Code::Intent::Rule](#codeintentrule) | code | [`rule.rb:11`](../../../../lib/plastic/workflows/code/intent/rule.rb#L11) |

### Code::Intent::Rule

The code workflow `:code_add_ruling`, in [`rule.rb:11`](../../../../lib/plastic/workflows/code/intent/rule.rb#L11).

Writes one ruling; fails on an unknown intent, or when --supersedes names no such ruling.

![How Code::Intent::Rule runs: its steps, where it stops, and its outcomes](code_add_ruling.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| find the intent | read |  | [`rule.rb:16`](../../../../lib/plastic/workflows/code/intent/rule.rb#L16) |
| no intent %{intent_id} in this store | gate, stops with exit 1 | `!context.intent.nil?` | [`rule.rb:20`](../../../../lib/plastic/workflows/code/intent/rule.rb#L20) |
| write the ruling | step | `!context.problem.nil? \|\| !context.id.nil?` | [`rule.rb:22`](../../../../lib/plastic/workflows/code/intent/rule.rb#L22) |
| %{problem} | gate, stops with exit 1 | `context.problem.nil?` | [`rule.rb:28`](../../../../lib/plastic/workflows/code/intent/rule.rb#L28) |
| say what was written | read |  | [`rule.rb:30`](../../../../lib/plastic/workflows/code/intent/rule.rb#L30) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:done` | always | finishes, exit 0; next: plastic intent brief %{intent_id} | [`rule.rb:34`](../../../../lib/plastic/workflows/code/intent/rule.rb#L34) |

It sets `intent`, `problem`, `id`.

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| no intent %{intent_id} in this store | 1 | prints no next: line | [`rule.rb:20`](../../../../lib/plastic/workflows/code/intent/rule.rb#L20) |
| %{problem} | 1 | prints no next: line | [`rule.rb:28`](../../../../lib/plastic/workflows/code/intent/rule.rb#L28) |
| ruling %{id} is on record | 0 | plastic intent brief %{intent_id} | [`rule.rb:34`](../../../../lib/plastic/workflows/code/intent/rule.rb#L34) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |
