# plastic node claim

Claim an open node and print its brief.

```sh
plastic node claim ID NODE
```

The command is `Node::Claim`, in [`claim.rb:9`](../../../../lib/plastic/commands/node/claim.rb#L9). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ID` | the intent | |
| `NODE` | the node | |

## What it touches

![What plastic node claim touches](component.svg)

## How the call flows

![The chain of workflows that plastic node claim runs](chain.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [Code::Node::Claim](#codenodeclaim) | code | [`claim.rb:12`](../../../../lib/plastic/workflows/code/node/claim.rb#L12) |

### Code::Node::Claim

The code workflow `:code_claim_node`, in [`claim.rb:12`](../../../../lib/plastic/workflows/code/node/claim.rb#L12).

Claims an open node whose needed nodes are done. The fourth claim of a node moves to needs_info instead, with the owner's question, and refuses. A refused claim keeps its routine run open, so the next call claims again.

![How Code::Node::Claim runs: its steps, where it stops, and its outcomes](code_claim_node.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| find the intent | read |  | [`claim.rb:19`](../../../../lib/plastic/workflows/code/node/claim.rb#L19) |
| no intent %{intent_id} in this store | gate, stops with exit 1 | `!context.intent.nil?` | [`claim.rb:23`](../../../../lib/plastic/workflows/code/node/claim.rb#L23) |
| forget a refusal of an earlier call | read |  | [`claim.rb:25`](../../../../lib/plastic/workflows/code/node/claim.rb#L25) |
| claim the node | step | `!context.result.nil?` | [`claim.rb:29`](../../../../lib/plastic/workflows/code/node/claim.rb#L29) |
| %{problem} | gate, stops with exit 3 | `context.result.to_s != "capped"` | [`claim.rb:45`](../../../../lib/plastic/workflows/code/node/claim.rb#L45) |
| %{problem} | gate, stops with exit 1 | `!STOPPED.include?(context.result.to_s)` | [`claim.rb:46`](../../../../lib/plastic/workflows/code/node/claim.rb#L46) |
| print the brief | read |  | [`claim.rb:48`](../../../../lib/plastic/workflows/code/node/claim.rb#L48) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:done` | always | finishes, exit 0; next: plastic node done %{intent_id} %{id} TEXT | [`claim.rb:56`](../../../../lib/plastic/workflows/code/node/claim.rb#L56) |

It sets `intent`, `result`, `node`, `problem`.

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| no intent %{intent_id} in this store | 1 | prints no next: line | [`claim.rb:23`](../../../../lib/plastic/workflows/code/node/claim.rb#L23) |
| %{problem} | 3 | prints no next: line | [`claim.rb:45`](../../../../lib/plastic/workflows/code/node/claim.rb#L45) |
| %{problem} | 1 | prints no next: line | [`claim.rb:46`](../../../../lib/plastic/workflows/code/node/claim.rb#L46) |
| node %{id} is claimed | 0 | plastic node done %{intent_id} %{id} TEXT | [`claim.rb:56`](../../../../lib/plastic/workflows/code/node/claim.rb#L56) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |
