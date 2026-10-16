# plastic intent spec

Print the grilling method, then the intent's open decisions.

```sh
plastic intent spec ID
```

The command is `Intent::Spec`, in [`spec.rb:9`](../../../../lib/plastic/commands/intent/spec.rb#L9). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ID` | the intent | |

## Components

![The components on the path of plastic intent spec](component.svg)

The figure shows the command, the workflows it runs, the classes behind them, and the databases and files they reach.

## The events of one call

![The workflows of plastic intent spec](workflows.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [Code::Intent::Spec](#codeintentspec) | code | [`spec.rb:14`](../../../../lib/plastic/workflows/code/intent/spec.rb#L14) |
| [Agent::Shared::AdvanceDelivery](#agentsharedadvancedelivery) | agent | [`advance_delivery.rb:10`](../../../../lib/plastic/workflows/agent/shared/advance_delivery.rb#L10) |

### Code::Intent::Spec

The code workflow `:code_show_spec`, in [`spec.rb:14`](../../../../lib/plastic/workflows/code/intent/spec.rb#L14).

Prints the grilling method, then the intent's open decisions; refuses an unknown id.

![How Code::Intent::Spec runs: its steps, where it stops, and its outcomes](code_show_spec.svg)

Its rows run in this order:

1. Read: find the intent. [`spec.rb:23`](../../../../lib/plastic/workflows/code/intent/spec.rb#L23)
2. Gate: passes when `!context.intent.nil?`; otherwise the call stops with exit 1 and prints no intent INTENT_ID in this store. [`spec.rb:27`](../../../../lib/plastic/workflows/code/intent/spec.rb#L27)
3. Read: print the grilling method. [`spec.rb:29`](../../../../lib/plastic/workflows/code/intent/spec.rb#L29)
4. Read: read the open decisions. [`spec.rb:34`](../../../../lib/plastic/workflows/code/intent/spec.rb#L34)
5. Read: read the go-ahead. [`go_ahead.rb:16`](../../../../lib/plastic/workflows/go_ahead.rb#L16)
6. Outcome `:open`, when `context.decisions.any?`: finishes with exit 0; next: plastic intent rule INTENT_ID TEXT. [`spec.rb:43`](../../../../lib/plastic/workflows/code/intent/spec.rb#L43)
7. Outcome `:no_criterion`, when `context.criteria.empty?`: finishes with exit 0; next: plastic sync up. [`spec.rb:45`](../../../../lib/plastic/workflows/code/intent/spec.rb#L45)
8. Outcome `:agent_needed`, when `!context.handoff_text.nil?`: starts the workflow [Agent::Shared::AdvanceDelivery](#agentsharedadvancedelivery). [`spec.rb:47`](../../../../lib/plastic/workflows/code/intent/spec.rb#L47)
9. Outcome `:done`, otherwise: finishes with exit 0; next: plastic auto INTENT_ID. [`spec.rb:48`](../../../../lib/plastic/workflows/code/intent/spec.rb#L48)

It sets `intent`, `decisions`, `criteria`, `why`, `handoff_text`.

### Agent::Shared::AdvanceDelivery

The agent workflow `:agent_advance_delivery`, in [`advance_delivery.rb:10`](../../../../lib/plastic/workflows/agent/shared/advance_delivery.rb#L10).

The harness performs judgment and records the result through commands.

![How Agent::Shared::AdvanceDelivery runs: its steps, where it stops, and its outcomes](agent_advance_delivery.svg)

Its rows run in this order:

1. Agent step: advance the delivery. Done when `context.handoff_text.nil?`; while it fails, the call prints its `say:` text. [`advance_delivery.rb:11`](../../../../lib/plastic/workflows/agent/shared/advance_delivery.rb#L11)
2. Outcome `:handoff`, when a step is left: hands off with exit 0; prints no next: line. [`advance_delivery.rb:12`](../../../../lib/plastic/workflows/agent/shared/advance_delivery.rb#L12)
3. Outcome `:done`, when every done check holds: finishes with exit 0; prints no next: line. [`advance_delivery.rb:13`](../../../../lib/plastic/workflows/agent/shared/advance_delivery.rb#L13)

The agent step "advance the delivery" prints:

> HANDOFF_TEXT

While a step is left, the call hands off with exit 0 from `:handoff`: it prints the `say:` text of each failing step and prints no next: line. The command writes nothing, so the call keeps no routine run row. The next call starts fresh and checks the steps again.

In the words of workflow engines, the rows are these four parts:

- **Trigger**: the call starts the workflow `Code::Intent::Spec`; each later workflow starts from an outcome of the one before it.
- **Activities**: 4 reads and 1 agent step.
- **Transitions**: 1 gate stops the call when its check fails; a step runs only while its done check fails; Spec goes to AdvanceDelivery on `:agent_needed`.
- **Outcomes**: `:open` of Spec, `:no_criterion` of Spec, `:done` of Spec, `:handoff` of AdvanceDelivery, `:done` of AdvanceDelivery end the call.

## What one call reads, writes and prints

![What one call of plastic intent spec reads, writes and prints](touches.svg)

| Place | Database or file | Tables | Reads or writes | Code |
| --- | --- | --- | --- | --- |
| the store folder | knowledge_graph.db | `documents` | reads | [`spec.rb:11`](../../../../lib/plastic/commands/intent/spec.rb#L11) |
| the store folder | work_graph.db | `approvals`, `edges`, `intents`, `nodes` | reads | [`spec.rb:11`](../../../../lib/plastic/commands/intent/spec.rb#L11) |

A second call runs the same rows again. A step runs again only when its done check fails.

| Step | Done when | The second call | Code |
| --- | --- | --- | --- |
| advance the delivery | `context.handoff_text.nil?` | skips it | [`advance_delivery.rb:11`](../../../../lib/plastic/workflows/agent/shared/advance_delivery.rb#L11) |

## How a call ends

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| no intent INTENT_ID in this store | 1 | prints no next: line | [`spec.rb:27`](../../../../lib/plastic/workflows/code/intent/spec.rb#L27) |
| an open decision is still unrecorded | 0 | plastic intent rule INTENT_ID TEXT | [`spec.rb:43`](../../../../lib/plastic/workflows/code/intent/spec.rb#L43) |
| the spec names no done criterion; write them in spec.md first | 0 | plastic sync up | [`spec.rb:45`](../../../../lib/plastic/workflows/code/intent/spec.rb#L45) |
| the spec carries no open decision | 0 | plastic auto INTENT_ID | [`spec.rb:48`](../../../../lib/plastic/workflows/code/intent/spec.rb#L48) |
| WHY | 0 | prints no next: line | [`advance_delivery.rb:12`](../../../../lib/plastic/workflows/agent/shared/advance_delivery.rb#L12) |
| the delivery instruction has been handled | 0 | prints no next: line | [`advance_delivery.rb:13`](../../../../lib/plastic/workflows/agent/shared/advance_delivery.rb#L13) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |

## What the page leaves out

Every call shares a few things that this page does not repeat; [the command DSL](../../dsl/README.md#what-every-call-shares) names them.

- No gate of this command refuses, so exit 3 never happens.
