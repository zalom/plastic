# plastic auto

Deliver one intent or one roadmap in auto mode: take the lock and print the worktree.

```sh
plastic auto ID
```

The command is `Auto`, in [`auto.rb:9`](../../../../lib/plastic/commands/auto.rb#L9). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ID` | the intent id or the roadmap slug | |

## What it touches

![What plastic auto touches](component.svg)

## How the call flows

![The chain of workflows that plastic auto runs](chain.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [Code::Auto::Pick](#codeautopick) | code | [`pick.rb:17`](../../../../lib/plastic/workflows/code/auto/pick.rb#L17) |
| [Code::Auto](#codeauto) | code | [`auto.rb:14`](../../../../lib/plastic/workflows/code/auto.rb#L14) |

### Code::Auto::Pick

The code workflow `:code_pick_delivery`, in [`pick.rb:17`](../../../../lib/plastic/workflows/code/auto/pick.rb#L17).

Turns the word `plastic auto` was given into the intent to deliver. A word shaped like an intent id is that intent. Any other word is a roadmap slug: its first item in flight that is not parked and not held by another session's live lock, in batch then item order. With none, it offers a ready item to start, or says the roadmap is delivered or waits.

![How Code::Auto::Pick runs: its steps, where it stops, and its outcomes](code_pick_delivery.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| forget what an earlier call picked | read |  | [`pick.rb:22`](../../../../lib/plastic/workflows/code/auto/pick.rb#L22) |
| no roadmap %{id} | gate, stops with exit 1 | `intent_word?(context) \|\| !context.retrieval.roadmap(context.id).nil?` | [`pick.rb:28`](../../../../lib/plastic/workflows/code/auto/pick.rb#L28) |
| pick the intent to deliver | read |  | [`pick.rb:31`](../../../../lib/plastic/workflows/code/auto/pick.rb#L31) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:intent` | when `!context.intent_id.nil?` | runs [Code::Auto](#codeauto) | [`pick.rb:58`](../../../../lib/plastic/workflows/code/auto/pick.rb#L58) |
| `:ready` | when `!context.ready_id.nil?` | finishes, exit 0; next: plastic roadmap open %{id} %{ready_id} | [`pick.rb:59`](../../../../lib/plastic/workflows/code/auto/pick.rb#L59) |
| `:delivered` | when `context.open.empty?` | finishes, exit 0; next: plastic roadmap show %{id} | [`pick.rb:61`](../../../../lib/plastic/workflows/code/auto/pick.rb#L61) |
| `:waiting` | otherwise | finishes, exit 0; next: plastic roadmap show %{id} | [`pick.rb:63`](../../../../lib/plastic/workflows/code/auto/pick.rb#L63) |

It sets `intent_id`, `ready_id`, `open`.

### Code::Auto

The code workflow `:code_start_auto`, in [`auto.rb:14`](../../../../lib/plastic/workflows/code/auto.rb#L14).

Arms delivery on an intent: refuses an open decision, no done criteria, no go-ahead row, a done or abandoned intent, or another session's live lock; fails with no session named; otherwise takes the lock and goes active, then prints the code worktree when the store's project names a repository.

![How Code::Auto runs: its steps, where it stops, and its outcomes](code_start_auto.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| read the intent and its spec | read |  | [`auto.rb:19`](../../../../lib/plastic/workflows/code/auto.rb#L19) |
| no intent %{intent_id} in this store | gate, stops with exit 1 | `!context.intent.nil?` | [`auto.rb:61`](../../../../lib/plastic/workflows/code/auto.rb#L61) |
| plastic auto names no session | gate, stops with exit 1 | `!context.session.nil?` | [`auto.rb:62`](../../../../lib/plastic/workflows/code/auto.rb#L62) |
| %{closed_problem} | gate, stops with exit 1 | `context.closed_problem.nil?` | [`auto.rb:63`](../../../../lib/plastic/workflows/code/auto.rb#L63) |
| %{spec_problem} | gate, stops with exit 1 | `context.spec_problem.nil?` | [`auto.rb:65`](../../../../lib/plastic/workflows/code/auto.rb#L65) |
| %{problem} | gate, stops with exit 3 | `context.problem.nil?` | [`auto.rb:67`](../../../../lib/plastic/workflows/code/auto.rb#L67) |
| take the lock and go active | step | `def self.delivery_started?(context) retrieval = context.retrieval intent_id = context.intent_id lock = retrieval.lock(intent_id) retrieval.intent(intent_id).status == "active" && lock&.session_id == context.session && lock.mode == "auto" && retrieval.liveness(lock).live? end` | [`auto.rb:77`](../../../../lib/plastic/workflows/code/auto.rb#L77) |
| name the code worktree | read |  | [`auto.rb:82`](../../../../lib/plastic/workflows/code/auto.rb#L82) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:done` | always | finishes, exit 0; next: plastic intent brief %{intent_id} | [`auto.rb:93`](../../../../lib/plastic/workflows/code/auto.rb#L93) |

It sets `problem`, `closed_problem`, `spec_problem`, `intent`.

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| no roadmap %{id} | 1 | prints no next: line | [`pick.rb:28`](../../../../lib/plastic/workflows/code/auto/pick.rb#L28) |
| item %{ready_id} is ready | 0 | plastic roadmap open %{id} %{ready_id} | [`pick.rb:59`](../../../../lib/plastic/workflows/code/auto/pick.rb#L59) |
| every item of %{id} is done or dropped | 0 | plastic roadmap show %{id} | [`pick.rb:61`](../../../../lib/plastic/workflows/code/auto/pick.rb#L61) |
| no item of %{id} is free to deliver yet | 0 | plastic roadmap show %{id} | [`pick.rb:63`](../../../../lib/plastic/workflows/code/auto/pick.rb#L63) |
| no intent %{intent_id} in this store | 1 | prints no next: line | [`auto.rb:61`](../../../../lib/plastic/workflows/code/auto.rb#L61) |
| plastic auto names no session | 1 | prints no next: line | [`auto.rb:62`](../../../../lib/plastic/workflows/code/auto.rb#L62) |
| %{closed_problem} | 1 | plastic next | [`auto.rb:63`](../../../../lib/plastic/workflows/code/auto.rb#L63) |
| %{spec_problem} | 1 | plastic intent spec %{intent_id} | [`auto.rb:65`](../../../../lib/plastic/workflows/code/auto.rb#L65) |
| %{problem} | 3 | prints no next: line | [`auto.rb:67`](../../../../lib/plastic/workflows/code/auto.rb#L67) |
| intent %{intent_id} is active | 0 | plastic intent brief %{intent_id} | [`auto.rb:93`](../../../../lib/plastic/workflows/code/auto.rb#L93) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |
