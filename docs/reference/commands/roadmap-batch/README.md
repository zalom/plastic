# plastic roadmap batch

Write one roadmap batch's goal and done criteria.

```sh
plastic roadmap batch SLUG N [--title TITLE] [--goal GOAL] [--done TEXT]
```

The command is `Roadmap::Batch`, in [`batch.rb:9`](../../../../lib/plastic/commands/roadmap/batch.rb#L9). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `SLUG` | the roadmap | |
| `N` | the batch's position, 1 and on | |
| `--title TITLE` | the batch's title |  |
| `--goal GOAL` | the batch's goal |  |
| `--done TEXT` | one done criterion; repeat for more | `[]` |

## What it touches

![What plastic roadmap batch touches](component.svg)

## How the call flows

![The chain of workflows that plastic roadmap batch runs](chain.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [Code::Roadmap::Batch](#coderoadmapbatch) | code | [`batch.rb:11`](../../../../lib/plastic/workflows/code/roadmap/batch.rb#L11) |

### Code::Roadmap::Batch

The code workflow `:code_write_roadmap_batch`, in [`batch.rb:11`](../../../../lib/plastic/workflows/code/roadmap/batch.rb#L11).

Writes a roadmap batch's goal and done criteria on a roadmap that exists.

![How Code::Roadmap::Batch runs: its steps, where it stops, and its outcomes](code_write_roadmap_batch.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| no roadmap %{slug} | gate, stops with exit 1 | `!context.retrieval.roadmap(context.slug).nil?` | [`batch.rb:14`](../../../../lib/plastic/workflows/code/roadmap/batch.rb#L14) |
| write the batch | step | `!context.batch.nil?` | [`batch.rb:20`](../../../../lib/plastic/workflows/code/roadmap/batch.rb#L20) |
| say what was written | read |  | [`batch.rb:25`](../../../../lib/plastic/workflows/code/roadmap/batch.rb#L25) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:done` | always | finishes, exit 0; next: plastic roadmap show %{slug} | [`batch.rb:29`](../../../../lib/plastic/workflows/code/roadmap/batch.rb#L29) |

It sets `batch`.

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| no roadmap %{slug} | 1 | plastic roadmap new %{slug} | [`batch.rb:14`](../../../../lib/plastic/workflows/code/roadmap/batch.rb#L14) |
| batch %{position} of %{slug} is written | 0 | plastic roadmap show %{slug} | [`batch.rb:29`](../../../../lib/plastic/workflows/code/roadmap/batch.rb#L29) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |
