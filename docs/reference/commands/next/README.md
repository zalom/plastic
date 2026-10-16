# plastic next

Pick the intent in play and offer its next command.

```sh
plastic next
```

The command is `Next`, in [`next.rb:8`](../../../../lib/plastic/commands/next.rb#L8). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

## What it touches

![What plastic next touches](component.svg)

## How the call flows

![The chain of workflows that plastic next runs](chain.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [Code::Next](#codenext) | code | [`next.rb:13`](../../../../lib/plastic/workflows/code/next.rb#L13) |
| [Agent::Shared::AdvanceDelivery](#agentsharedadvancedelivery) | agent | [`advance_delivery.rb:10`](../../../../lib/plastic/workflows/agent/shared/advance_delivery.rb#L10) |

### Code::Next

The code workflow `:code_pick_next`, in [`next.rb:13`](../../../../lib/plastic/workflows/code/next.rb#L13).

Picks the intent this session is working on and offers its next command: the spec, the start, the brief, a failed node, the check or the ready list. Several candidates offer status; none offers a new intent.

![How Code::Next runs: its steps, where it stops, and its outcomes](code_pick_next.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| pick the intent and its next command | read |  | [`next.rb:18`](../../../../lib/plastic/workflows/code/next.rb#L18) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:agent_needed` | when `!context.handoff_text.nil?` | runs [Agent::Shared::AdvanceDelivery](#agentsharedadvancedelivery) | [`next.rb:23`](../../../../lib/plastic/workflows/code/next.rb#L23) |
| `:nothing` | when `context.next_command.nil?` | finishes, exit 0; prints no next: line | [`next.rb:24`](../../../../lib/plastic/workflows/code/next.rb#L24) |
| `:done` | otherwise | finishes, exit 0; next: %{next_command} | [`next.rb:25`](../../../../lib/plastic/workflows/code/next.rb#L25) |

It sets `next_command`, `why`, `handoff_text`.

### Agent::Shared::AdvanceDelivery

The agent workflow `:agent_advance_delivery`, in [`advance_delivery.rb:10`](../../../../lib/plastic/workflows/agent/shared/advance_delivery.rb#L10).

The harness performs judgment and records the result through commands.

![How Agent::Shared::AdvanceDelivery runs: its steps, where it stops, and its outcomes](agent_advance_delivery.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| advance the delivery | agent step | `context.handoff_text.nil?` | [`advance_delivery.rb:11`](../../../../lib/plastic/workflows/agent/shared/advance_delivery.rb#L11) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:handoff` | when a step is left | hands off, exit 0; prints no next: line | [`advance_delivery.rb:12`](../../../../lib/plastic/workflows/agent/shared/advance_delivery.rb#L12) |
| `:done` | when every done check holds | finishes, exit 0; prints no next: line | [`advance_delivery.rb:13`](../../../../lib/plastic/workflows/agent/shared/advance_delivery.rb#L13) |

The agent step "advance the delivery" prints:

> %{handoff_text}

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| %{why} | 0 | prints no next: line | [`next.rb:24`](../../../../lib/plastic/workflows/code/next.rb#L24) |
| %{why} | 0 | %{next_command} | [`next.rb:25`](../../../../lib/plastic/workflows/code/next.rb#L25) |
| %{why} | 0 | prints no next: line | [`advance_delivery.rb:12`](../../../../lib/plastic/workflows/agent/shared/advance_delivery.rb#L12) |
| the delivery instruction has been handled | 0 | prints no next: line | [`advance_delivery.rb:13`](../../../../lib/plastic/workflows/agent/shared/advance_delivery.rb#L13) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |
