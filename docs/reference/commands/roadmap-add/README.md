# plastic roadmap add

Add an item to a roadmap batch, with the items it needs.

```sh
plastic roadmap add SLUG N ITEM [--title TITLE] [--goal GOAL] [--done TEXT] [--needs ITEM]
```

The command is `Roadmap::Add`, in [`add.rb:9`](../../../../lib/plastic/commands/roadmap/add.rb#L9). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `SLUG` | the roadmap | |
| `N` | the batch the item belongs to | |
| `ITEM` | the item's id | |
| `--title TITLE` | the item's title |  |
| `--goal GOAL` | the item's goal |  |
| `--done TEXT` | one done criterion; repeat for more | `[]` |
| `--needs ITEM` | an item this one needs; repeat for more | `[]` |

## What it touches

![What plastic roadmap add touches](component.svg)

## How the call flows

![The chain of workflows that plastic roadmap add runs](chain.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [Code::Roadmap::Add](#coderoadmapadd) | code | [`add.rb:12`](../../../../lib/plastic/workflows/code/roadmap/add.rb#L12) |

### Code::Roadmap::Add

The code workflow `:code_add_roadmap_item`, in [`add.rb:12`](../../../../lib/plastic/workflows/code/roadmap/add.rb#L12).

Adds one item to a roadmap batch, guarded against a missing batch, a predecessor not on the roadmap, and a loop over roadmap_edges.

![How Code::Roadmap::Add runs: its steps, where it stops, and its outcomes](code_add_roadmap_item.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| forget a stop of an earlier call | read |  | [`code_workflow.rb:54`](../../../../lib/plastic/code_workflow.rb#L54) |
| add the item | step | `!context.item.nil? \|\| !context.problem.nil?` | [`add.rb:19`](../../../../lib/plastic/workflows/code/roadmap/add.rb#L19) |
| %{problem} | gate, stops with exit 1 | `context.kind != :failure` | [`add.rb:28`](../../../../lib/plastic/workflows/code/roadmap/add.rb#L28) |
| %{problem} | gate, stops with exit 3 | `context.kind != :refusal` | [`add.rb:29`](../../../../lib/plastic/workflows/code/roadmap/add.rb#L29) |
| say what was added | read |  | [`add.rb:31`](../../../../lib/plastic/workflows/code/roadmap/add.rb#L31) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:done` | always | finishes, exit 0; next: plastic roadmap show %{slug} | [`add.rb:35`](../../../../lib/plastic/workflows/code/roadmap/add.rb#L35) |

It sets `problem`, `kind`, `item`.

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| %{problem} | 1 | prints no next: line | [`add.rb:28`](../../../../lib/plastic/workflows/code/roadmap/add.rb#L28) |
| %{problem} | 3 | prints no next: line | [`add.rb:29`](../../../../lib/plastic/workflows/code/roadmap/add.rb#L29) |
| item %{item_id} is on roadmap %{slug} | 0 | plastic roadmap show %{slug} | [`add.rb:35`](../../../../lib/plastic/workflows/code/roadmap/add.rb#L35) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |
