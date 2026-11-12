# plastic intent revise

Rewrite an intent's What and Why after grilling, keeping the old text as a revision.

```sh
plastic intent revise ID LINE [--why TEXT] [--dry-run]
```

The command is `Intent::Revise`, in [`revise.rb:10`](../../../../lib/plastic/commands/intent/revise.rb#L10). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ID` | the intent | |
| `LINE` | the new What, the intent line | |
| `--why TEXT` | the new Why, the lead text of ## Context |  |
| `--dry-run` | print the change and write nothing | `false` |

## What it touches

![What plastic intent revise touches](component.svg)

## How the call flows

![The chain of workflows that plastic intent revise runs](chain.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [Code::Intent::Revise](#codeintentrevise) | code | [`revise.rb:11`](../../../../lib/plastic/workflows/code/intent/revise.rb#L11) |

### Code::Intent::Revise

The code workflow `:code_revise_intent`, in [`revise.rb:11`](../../../../lib/plastic/workflows/code/intent/revise.rb#L11).

Rewrites an intent's What and Why; a done or abandoned intent refuses, and a dry run prints the change and writes nothing.

![How Code::Intent::Revise runs: its steps, where it stops, and its outcomes](code_revise_intent.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| find the intent | read |  | [`revise.rb:18`](../../../../lib/plastic/workflows/code/intent/revise.rb#L18) |
| no intent %{intent_id} in this store | gate, stops with exit 1 | `!context.intent.nil?` | [`revise.rb:23`](../../../../lib/plastic/workflows/code/intent/revise.rb#L23) |
| intent %{intent_id} is %{status}; a closed intent keeps its What and Why | gate, stops with exit 1 | `!CLOSED.include?(context.status)` | [`revise.rb:25`](../../../../lib/plastic/workflows/code/intent/revise.rb#L25) |
| check the change | read |  | [`revise.rb:29`](../../../../lib/plastic/workflows/code/intent/revise.rb#L29) |
| %{problem} | gate, stops with exit 1 | `context.problem.nil?` | [`revise.rb:34`](../../../../lib/plastic/workflows/code/intent/revise.rb#L34) |
| show the change | read |  | [`revise.rb:36`](../../../../lib/plastic/workflows/code/intent/revise.rb#L36) |
| write the revision | step | `context.dry_run \|\| !context.new_reference.nil?` | [`revise.rb:43`](../../../../lib/plastic/workflows/code/intent/revise.rb#L43) |
| say what was written | read |  | [`revise.rb:47`](../../../../lib/plastic/workflows/code/intent/revise.rb#L47) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:previewed` | when `context.dry_run` | finishes, exit 0; next: %{original_command} | [`revise.rb:52`](../../../../lib/plastic/workflows/code/intent/revise.rb#L52) |
| `:done` | otherwise | finishes, exit 0; prints no next: line | [`revise.rb:54`](../../../../lib/plastic/workflows/code/intent/revise.rb#L54) |

It sets `intent`, `status`, `change`, `problem`, `old_reference`, `new_reference`.

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| no intent %{intent_id} in this store | 1 | prints no next: line | [`revise.rb:23`](../../../../lib/plastic/workflows/code/intent/revise.rb#L23) |
| intent %{intent_id} is %{status}; a closed intent keeps its What and Why | 1 | plastic next | [`revise.rb:25`](../../../../lib/plastic/workflows/code/intent/revise.rb#L25) |
| %{problem} | 1 | prints no next: line | [`revise.rb:34`](../../../../lib/plastic/workflows/code/intent/revise.rb#L34) |
| the dry run wrote nothing | 0 | %{original_command} | [`revise.rb:52`](../../../../lib/plastic/workflows/code/intent/revise.rb#L52) |
| the rows and the files hold the new What and Why | 0 | prints no next: line | [`revise.rb:54`](../../../../lib/plastic/workflows/code/intent/revise.rb#L54) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |
