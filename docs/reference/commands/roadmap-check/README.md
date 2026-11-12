# plastic roadmap check

List a roadmap's loops, dangling edges and items with no intent.

```sh
plastic roadmap check SLUG
```

The command is `Roadmap::Check`, in [`check.rb:9`](../../../../lib/plastic/commands/roadmap/check.rb#L9). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `SLUG` | the roadmap | |

## What it touches

![What plastic roadmap check touches](component.svg)

## How the call flows

![The chain of workflows that plastic roadmap check runs](chain.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [Code::Roadmap::Check](#coderoadmapcheck) | code | [`check.rb:11`](../../../../lib/plastic/workflows/code/roadmap/check.rb#L11) |

### Code::Roadmap::Check

The code workflow `:code_check_roadmap`, in [`check.rb:11`](../../../../lib/plastic/workflows/code/roadmap/check.rb#L11).

Prints each finding, or "no findings"; a finding fails the call.

![How Code::Roadmap::Check runs: its steps, where it stops, and its outcomes](code_check_roadmap.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| no roadmap %{slug} | gate, stops with exit 1 | `!context.retrieval.roadmap(context.slug).nil?` | [`check.rb:16`](../../../../lib/plastic/workflows/code/roadmap/check.rb#L16) |
| find problems | read |  | [`check.rb:18`](../../../../lib/plastic/workflows/code/roadmap/check.rb#L18) |
| see the findings above | gate, stops with exit 1 | `context.findings.empty?` | [`check.rb:30`](../../../../lib/plastic/workflows/code/roadmap/check.rb#L30) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:done` | always | finishes, exit 0; next: plastic roadmap show %{slug} | [`check.rb:32`](../../../../lib/plastic/workflows/code/roadmap/check.rb#L32) |

It sets `findings`.

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| no roadmap %{slug} | 1 | prints no next: line | [`check.rb:16`](../../../../lib/plastic/workflows/code/roadmap/check.rb#L16) |
| see the findings above | 1 | prints no next: line | [`check.rb:30`](../../../../lib/plastic/workflows/code/roadmap/check.rb#L30) |
| roadmap %{slug} has no findings | 0 | plastic roadmap show %{slug} | [`check.rb:32`](../../../../lib/plastic/workflows/code/roadmap/check.rb#L32) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |
