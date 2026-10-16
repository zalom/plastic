# plastic intent lock status

Print the session that holds an intent's lock, and its worktree.

```sh
plastic intent lock status ID
```

The command is `Intent::Lock::Status`, in [`status.rb:10`](../../../../lib/plastic/commands/intent/lock/status.rb#L10). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ID` | the intent | |

## What it touches

![What plastic intent lock status touches](component.svg)

## How the call flows

![The chain of workflows that plastic intent lock status runs](chain.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [Code::Intent::Lock::Status](#codeintentlockstatus) | code | [`status.rb:15`](../../../../lib/plastic/workflows/code/intent/lock/status.rb#L15) |
| [Agent::Shared::AdvanceDelivery](#agentsharedadvancedelivery) | agent | [`advance_delivery.rb:10`](../../../../lib/plastic/workflows/agent/shared/advance_delivery.rb#L10) |

### Code::Intent::Lock::Status

The code workflow `:code_show_lock`, in [`status.rb:15`](../../../../lib/plastic/workflows/code/intent/lock/status.rb#L15).

Prints an intent's lock row: the session, the mode, when it was taken and renewed, whether it is still live and why; then the code worktree when the store's project names a repository. Refuses an unknown id.

![How Code::Intent::Lock::Status runs: its steps, where it stops, and its outcomes](code_show_lock.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| find the intent | read |  | [`status.rb:22`](../../../../lib/plastic/workflows/code/intent/lock/status.rb#L22) |
| no intent %{intent_id} in this store | gate, stops with exit 1 | `!context.intent.nil?` | [`status.rb:27`](../../../../lib/plastic/workflows/code/intent/lock/status.rb#L27) |
| print the lock and the worktree | read |  | [`status.rb:29`](../../../../lib/plastic/workflows/code/intent/lock/status.rb#L29) |
| read the go-ahead | read |  | [`go_ahead.rb:16`](../../../../lib/plastic/workflows/go_ahead.rb#L16) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:closed` | when `%w[done abandoned].include?(context.intent.status)` | finishes, exit 0; prints no next: line | [`status.rb:51`](../../../../lib/plastic/workflows/code/intent/lock/status.rb#L51) |
| `:agent_needed` | when `context.state != "live" && !context.handoff_text.nil?` | runs [Agent::Shared::AdvanceDelivery](#agentsharedadvancedelivery) | [`status.rb:53`](../../../../lib/plastic/workflows/code/intent/lock/status.rb#L53) |
| `:none` | when `context.state == "none"` | finishes, exit 0; next: plastic auto %{intent_id} | [`status.rb:54`](../../../../lib/plastic/workflows/code/intent/lock/status.rb#L54) |
| `:expired` | when `context.state == "expired"` | finishes, exit 0; next: plastic auto %{intent_id} | [`status.rb:56`](../../../../lib/plastic/workflows/code/intent/lock/status.rb#L56) |
| `:live` | otherwise | finishes, exit 0; next: plastic intent brief %{intent_id} | [`status.rb:58`](../../../../lib/plastic/workflows/code/intent/lock/status.rb#L58) |

It sets `intent`, `state`, `status`, `why`, `handoff_text`.

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
| no intent %{intent_id} in this store | 1 | prints no next: line | [`status.rb:27`](../../../../lib/plastic/workflows/code/intent/lock/status.rb#L27) |
| intent %{intent_id} is %{status} | 0 | prints no next: line | [`status.rb:51`](../../../../lib/plastic/workflows/code/intent/lock/status.rb#L51) |
| intent %{intent_id} holds no lock | 0 | plastic auto %{intent_id} | [`status.rb:54`](../../../../lib/plastic/workflows/code/intent/lock/status.rb#L54) |
| the lock of intent %{intent_id} expired, and plastic auto takes it over | 0 | plastic auto %{intent_id} | [`status.rb:56`](../../../../lib/plastic/workflows/code/intent/lock/status.rb#L56) |
| a live session holds intent %{intent_id} | 0 | plastic intent brief %{intent_id} | [`status.rb:58`](../../../../lib/plastic/workflows/code/intent/lock/status.rb#L58) |
| %{why} | 0 | prints no next: line | [`advance_delivery.rb:12`](../../../../lib/plastic/workflows/agent/shared/advance_delivery.rb#L12) |
| the delivery instruction has been handled | 0 | prints no next: line | [`advance_delivery.rb:13`](../../../../lib/plastic/workflows/agent/shared/advance_delivery.rb#L13) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |
