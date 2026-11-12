# plastic roadmap drop

Mark a roadmap item dropped; its edges stay as rows.

```sh
plastic roadmap drop SLUG ITEM [--dry-run]
```

The command is `Roadmap::Drop`, in [`drop.rb:9`](../../../../lib/plastic/commands/roadmap/drop.rb#L9). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `SLUG` | the roadmap | |
| `ITEM` | the item to drop | |
| `--dry-run` | preview the call in a disposable copy | `false` |

## What it touches

![What plastic roadmap drop touches](component.svg)

## How the call flows

![The chain of workflows that plastic roadmap drop runs](chain.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [Code::Roadmap::Drop](#coderoadmapdrop) | code | [`drop.rb:11`](../../../../lib/plastic/workflows/code/roadmap/drop.rb#L11) |

### Code::Roadmap::Drop

The code workflow `:code_drop_roadmap_item`, in [`drop.rb:11`](../../../../lib/plastic/workflows/code/roadmap/drop.rb#L11).

Marks a roadmap item dropped. Its edges stay; items after it stop waiting for it, since a dropped predecessor counts as resolved.

![How Code::Roadmap::Drop runs: its steps, where it stops, and its outcomes](code_drop_roadmap_item.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| no roadmap %{slug} | gate, stops with exit 1 | `!context.retrieval.roadmap(context.slug).nil?` | [`drop.rb:16`](../../../../lib/plastic/workflows/code/roadmap/drop.rb#L16) |
| find the item | read |  | [`drop.rb:18`](../../../../lib/plastic/workflows/code/roadmap/drop.rb#L18) |
| no item %{item_id} on roadmap %{slug} | gate, stops with exit 1 | `!context.item.nil?` | [`drop.rb:22`](../../../../lib/plastic/workflows/code/roadmap/drop.rb#L22) |
| drop the item | step | `context.dropped` | [`drop.rb:24`](../../../../lib/plastic/workflows/code/roadmap/drop.rb#L24) |
| say what was dropped | read |  | [`drop.rb:28`](../../../../lib/plastic/workflows/code/roadmap/drop.rb#L28) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:done` | always | finishes, exit 0; next: plastic roadmap next %{slug} | [`drop.rb:32`](../../../../lib/plastic/workflows/code/roadmap/drop.rb#L32) |

It sets `item`, `dropped`.

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| no roadmap %{slug} | 1 | prints no next: line | [`drop.rb:16`](../../../../lib/plastic/workflows/code/roadmap/drop.rb#L16) |
| no item %{item_id} on roadmap %{slug} | 1 | prints no next: line | [`drop.rb:22`](../../../../lib/plastic/workflows/code/roadmap/drop.rb#L22) |
| item %{item_id} no longer blocks its successors | 0 | plastic roadmap next %{slug} | [`drop.rb:32`](../../../../lib/plastic/workflows/code/roadmap/drop.rb#L32) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |
