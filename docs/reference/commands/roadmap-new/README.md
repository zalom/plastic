# plastic roadmap new

Create a roadmap; write its batches with roadmap batch.

```sh
plastic roadmap new NAME [--title TITLE] [--goal GOAL]
```

The command is `Roadmap::New`, in [`new.rb:9`](../../../../lib/plastic/commands/roadmap/new.rb#L9). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `NAME` | the roadmap's name | |
| `--title TITLE` | the roadmap's title; the name when absent |  |
| `--goal GOAL` | the roadmap's goal |  |

## What it touches

![What plastic roadmap new touches](component.svg)

## How the call flows

![The chain of workflows that plastic roadmap new runs](chain.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [Code::Roadmap::New](#coderoadmapnew) | code | [`new.rb:10`](../../../../lib/plastic/workflows/code/roadmap/new.rb#L10) |

### Code::Roadmap::New

The code workflow `:code_create_roadmap`, in [`new.rb:10`](../../../../lib/plastic/workflows/code/roadmap/new.rb#L10).

Creates a roadmap row and offers its first batch.

![How Code::Roadmap::New runs: its steps, where it stops, and its outcomes](code_create_roadmap.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| roadmap %{slug} already exists | gate, stops with exit 1 | `context.retrieval.roadmap(context.slug).nil?` | [`new.rb:13`](../../../../lib/plastic/workflows/code/roadmap/new.rb#L13) |
| create the roadmap | step | `!context.roadmap.nil?` | [`new.rb:19`](../../../../lib/plastic/workflows/code/roadmap/new.rb#L19) |
| say what was created | read |  | [`new.rb:23`](../../../../lib/plastic/workflows/code/roadmap/new.rb#L23) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:done` | always | finishes, exit 0; next: plastic roadmap batch %{slug} 1 | [`new.rb:27`](../../../../lib/plastic/workflows/code/roadmap/new.rb#L27) |

It sets `roadmap`.

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| roadmap %{slug} already exists | 1 | plastic roadmap show %{slug} | [`new.rb:13`](../../../../lib/plastic/workflows/code/roadmap/new.rb#L13) |
| roadmap %{slug} exists and has no batch yet | 0 | plastic roadmap batch %{slug} 1 | [`new.rb:27`](../../../../lib/plastic/workflows/code/roadmap/new.rb#L27) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |
