# plastic intent lock status

Print the session that holds an intent's lock, and its worktree.

```sh
plastic intent lock status ID
```

The command is `Intent::Lock::Status`, in [`status.rb:10`](../../../../lib/plastic/commands/intent/lock/status.rb#L10). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ID` | the intent | |

## Components

![The components on the path of plastic intent lock status](component.svg)

The figure shows the command, the workflows it runs, the classes behind them, and the databases and files they reach.

## The events of one call

![The workflows of plastic intent lock status](workflows.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [Code::Intent::Lock::Status](#codeintentlockstatus) | code | [`status.rb:15`](../../../../lib/plastic/workflows/code/intent/lock/status.rb#L15) |
| [Agent::Shared::AdvanceDelivery](#agentsharedadvancedelivery) | agent | [`advance_delivery.rb:10`](../../../../lib/plastic/workflows/agent/shared/advance_delivery.rb#L10) |

### Code::Intent::Lock::Status

The code workflow `:code_show_lock`, in [`status.rb:15`](../../../../lib/plastic/workflows/code/intent/lock/status.rb#L15).

Prints an intent's lock row: the session, the mode, when it was taken and renewed, whether it is still live and why; then the code worktree when the store's project names a repository. Refuses an unknown id.

![How Code::Intent::Lock::Status runs: its steps, where it stops, and its outcomes](code_show_lock.svg)

Its rows run in this order:

1. Read: find the intent. [`status.rb:22`](../../../../lib/plastic/workflows/code/intent/lock/status.rb#L22)
2. Gate: passes when `!context.intent.nil?`; otherwise the call stops with exit 1 and prints no intent INTENT_ID in this store. [`status.rb:27`](../../../../lib/plastic/workflows/code/intent/lock/status.rb#L27)
3. Read: print the lock and the worktree. [`status.rb:29`](../../../../lib/plastic/workflows/code/intent/lock/status.rb#L29)
4. Read: read the go-ahead. [`go_ahead.rb:16`](../../../../lib/plastic/workflows/go_ahead.rb#L16)
5. Outcome `:closed`, when `%w[done abandoned].include?(context.intent.status)`: finishes with exit 0; prints no next: line. [`status.rb:51`](../../../../lib/plastic/workflows/code/intent/lock/status.rb#L51)
6. Outcome `:agent_needed`, when `context.state != "live" && !context.handoff_text.nil?`: starts the workflow [Agent::Shared::AdvanceDelivery](#agentsharedadvancedelivery). [`status.rb:53`](../../../../lib/plastic/workflows/code/intent/lock/status.rb#L53)
7. Outcome `:none`, when `context.state == "none"`: finishes with exit 0; next: plastic auto INTENT_ID. [`status.rb:54`](../../../../lib/plastic/workflows/code/intent/lock/status.rb#L54)
8. Outcome `:expired`, when `context.state == "expired"`: finishes with exit 0; next: plastic auto INTENT_ID. [`status.rb:56`](../../../../lib/plastic/workflows/code/intent/lock/status.rb#L56)
9. Outcome `:live`, otherwise: finishes with exit 0; next: plastic intent brief INTENT_ID. [`status.rb:58`](../../../../lib/plastic/workflows/code/intent/lock/status.rb#L58)

It sets `intent`, `state`, `status`, `why`, `handoff_text`.

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

- **Trigger**: the call starts the workflow `Code::Intent::Lock::Status`; each later workflow starts from an outcome of the one before it.
- **Activities**: 3 reads and 1 agent step.
- **Transitions**: 1 gate stops the call when its check fails; a step runs only while its done check fails; Status goes to AdvanceDelivery on `:agent_needed`.
- **Outcomes**: `:closed` of Status, `:none` of Status, `:expired` of Status, `:live` of Status, `:handoff` of AdvanceDelivery, `:done` of AdvanceDelivery end the call.

## What one call reads, writes and prints

![What one call of plastic intent lock status reads, writes and prints](touches.svg)

| Place | Database or file | Tables | Reads or writes | Code |
| --- | --- | --- | --- | --- |
| the store folder | knowledge_graph.db | `documents` | reads | found in the code, not declared |
| the home folder | local.db | `locks`, `sessions` | reads | found in the code, not declared |
| the store folder | work_graph.db | `approvals`, `edges`, `intents`, `nodes` | reads | [`status.rb:12`](../../../../lib/plastic/commands/intent/lock/status.rb#L12) |

A second call runs the same rows again. A step runs again only when its done check fails.

| Step | Done when | The second call | Code |
| --- | --- | --- | --- |
| advance the delivery | `context.handoff_text.nil?` | skips it | [`advance_delivery.rb:11`](../../../../lib/plastic/workflows/agent/shared/advance_delivery.rb#L11) |

## How a call ends

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| no intent INTENT_ID in this store | 1 | prints no next: line | [`status.rb:27`](../../../../lib/plastic/workflows/code/intent/lock/status.rb#L27) |
| intent INTENT_ID is STATUS | 0 | prints no next: line | [`status.rb:51`](../../../../lib/plastic/workflows/code/intent/lock/status.rb#L51) |
| intent INTENT_ID holds no lock | 0 | plastic auto INTENT_ID | [`status.rb:54`](../../../../lib/plastic/workflows/code/intent/lock/status.rb#L54) |
| the lock of intent INTENT_ID expired, and plastic auto takes it over | 0 | plastic auto INTENT_ID | [`status.rb:56`](../../../../lib/plastic/workflows/code/intent/lock/status.rb#L56) |
| a live session holds intent INTENT_ID | 0 | plastic intent brief INTENT_ID | [`status.rb:58`](../../../../lib/plastic/workflows/code/intent/lock/status.rb#L58) |
| WHY | 0 | prints no next: line | [`advance_delivery.rb:12`](../../../../lib/plastic/workflows/agent/shared/advance_delivery.rb#L12) |
| the delivery instruction has been handled | 0 | prints no next: line | [`advance_delivery.rb:13`](../../../../lib/plastic/workflows/agent/shared/advance_delivery.rb#L13) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |

## What the page leaves out

Every call shares a few things that this page does not repeat; [the command DSL](../../dsl/README.md#what-every-call-shares) names them.

- No gate of this command refuses, so exit 3 never happens.
