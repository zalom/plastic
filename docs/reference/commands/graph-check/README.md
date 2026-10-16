# plastic graph check

Find a done node with no findings, an isolated node, a retry cap or no done criterion.

Runs the five findings of one intent's work graph and its spec.

```sh
plastic graph check ID
```

The command is `Graph::Check`, in [`check.rb:9`](../../../../lib/plastic/commands/graph/check.rb#L9). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ID` | the intent | |

## What it touches

![What plastic graph check touches](component.svg)

## How the call flows

![The chain of workflows that plastic graph check runs](chain.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [Code::Graph::Check](#codegraphcheck) | code | [`check.rb:11`](../../../../lib/plastic/workflows/code/graph/check.rb#L11) |

### Code::Graph::Check

The code workflow `:code_check_graph`, in [`check.rb:11`](../../../../lib/plastic/workflows/code/graph/check.rb#L11).

Prints each finding, or "no findings"; a finding fails the call.

![How Code::Graph::Check runs: its steps, where it stops, and its outcomes](code_check_graph.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| find the intent | read |  | [`check.rb:16`](../../../../lib/plastic/workflows/code/graph/check.rb#L16) |
| no intent %{intent_id} in this store | gate, stops with exit 1 | `!context.intent.nil?` | [`check.rb:20`](../../../../lib/plastic/workflows/code/graph/check.rb#L20) |
| find problems | read |  | [`check.rb:22`](../../../../lib/plastic/workflows/code/graph/check.rb#L22) |
| see the findings above | gate, stops with exit 1 | `context.findings.empty?` | [`check.rb:34`](../../../../lib/plastic/workflows/code/graph/check.rb#L34) |
| find the first ready node | read |  | [`check.rb:36`](../../../../lib/plastic/workflows/code/graph/check.rb#L36) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:nothing` | when `context.first.nil?` | finishes, exit 0; prints no next: line | [`check.rb:40`](../../../../lib/plastic/workflows/code/graph/check.rb#L40) |
| `:done` | otherwise | finishes, exit 0; next: plastic node claim %{intent_id} %{first} | [`check.rb:41`](../../../../lib/plastic/workflows/code/graph/check.rb#L41) |

It sets `intent`, `findings`, `first`.

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| no intent %{intent_id} in this store | 1 | prints no next: line | [`check.rb:20`](../../../../lib/plastic/workflows/code/graph/check.rb#L20) |
| see the findings above | 1 | prints no next: line | [`check.rb:34`](../../../../lib/plastic/workflows/code/graph/check.rb#L34) |
| no node is ready to claim | 0 | prints no next: line | [`check.rb:40`](../../../../lib/plastic/workflows/code/graph/check.rb#L40) |
| node %{first} is ready | 0 | plastic node claim %{intent_id} %{first} | [`check.rb:41`](../../../../lib/plastic/workflows/code/graph/check.rb#L41) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |
