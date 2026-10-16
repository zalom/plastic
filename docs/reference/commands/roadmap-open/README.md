# plastic roadmap open

Open a ready item's intent, with its spec held in rows.

```sh
plastic roadmap open SLUG ITEM
```

The command is `Roadmap::Open`, in [`open.rb:9`](../../../../lib/plastic/commands/roadmap/open.rb#L9). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `SLUG` | the roadmap | |
| `ITEM` | the item to open | |

## What it touches

![What plastic roadmap open touches](component.svg)

## How the call flows

![The chain of workflows that plastic roadmap open runs](chain.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [Code::Roadmap::Open](#coderoadmapopen) | code | [`open.rb:11`](../../../../lib/plastic/workflows/code/roadmap/open.rb#L11) |

### Code::Roadmap::Open

The code workflow `:code_open_roadmap_item`, in [`open.rb:11`](../../../../lib/plastic/workflows/code/roadmap/open.rb#L11).

Opens a ready item's intent, its spec.md holding the batch and item's goal and done criteria, then links the intent to the roadmap.

![How Code::Roadmap::Open runs: its steps, where it stops, and its outcomes](code_open_roadmap_item.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| forget a stop of an earlier call | read |  | [`code_workflow.rb:54`](../../../../lib/plastic/code_workflow.rb#L54) |
| open the item's intent | step | `!context.intent_id.nil? \|\| !context.problem.nil?` | [`open.rb:18`](../../../../lib/plastic/workflows/code/roadmap/open.rb#L18) |
| %{problem} | gate, stops with exit 1 | `context.kind != :failure` | [`open.rb:25`](../../../../lib/plastic/workflows/code/roadmap/open.rb#L25) |
| %{problem} | gate, stops with exit 3 | `context.kind != :refusal` | [`open.rb:26`](../../../../lib/plastic/workflows/code/roadmap/open.rb#L26) |
| say what was opened | read |  | [`open.rb:28`](../../../../lib/plastic/workflows/code/roadmap/open.rb#L28) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:done` | always | finishes, exit 0; next: plastic intent brief %{intent_id} | [`open.rb:32`](../../../../lib/plastic/workflows/code/roadmap/open.rb#L32) |

It sets `problem`, `kind`, `intent_id`.

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| %{problem} | 1 | prints no next: line | [`open.rb:25`](../../../../lib/plastic/workflows/code/roadmap/open.rb#L25) |
| %{problem} | 3 | prints no next: line | [`open.rb:26`](../../../../lib/plastic/workflows/code/roadmap/open.rb#L26) |
| item %{item_id} opened as intent %{intent_id} | 0 | plastic intent brief %{intent_id} | [`open.rb:32`](../../../../lib/plastic/workflows/code/roadmap/open.rb#L32) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |
