# plastic intent judge

Print the steps that start the judge of an intent.

```sh
plastic intent judge ID
```

The command is `Intent::Judge`, in [`judge.rb:9`](../../../../lib/plastic/commands/intent/judge.rb#L9). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ID` | the intent | |

## What it touches

![What plastic intent judge touches](component.svg)

## How the call flows

![The chain of workflows that plastic intent judge runs](chain.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [Code::Intent::Judge](#codeintentjudge) | code | [`judge.rb:12`](../../../../lib/plastic/workflows/code/intent/judge.rb#L12) |
| [Agent::Intent::Judge](#agentintentjudge) | agent | [`judge.rb:11`](../../../../lib/plastic/workflows/agent/intent/judge.rb#L11) |

### Code::Intent::Judge

The code workflow `:code_prepare_judge`, in [`judge.rb:12`](../../../../lib/plastic/workflows/code/intent/judge.rb#L12).

Reads the intent and its judge rounds: a missing or closed intent fails, both rounds used is the owner's step.

![How Code::Intent::Judge runs: its steps, where it stops, and its outcomes](code_prepare_judge.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| check the intent | read |  | [`judge.rb:17`](../../../../lib/plastic/workflows/code/intent/judge.rb#L17) |
| %{problem} | gate, stops with exit 1 | `context.problem.nil?` | [`judge.rb:21`](../../../../lib/plastic/workflows/code/intent/judge.rb#L21) |
| the judge's review round of intent %{intent_id} is used; the owner decides between abandoning the intent and a follow-up intent | gate, stops with exit 3 | `!Graph::Work::Completion::Review.of(context).used_up?` | [`review_round.rb:11`](../../../../lib/plastic/workflows/review_round.rb#L11) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:accepted` | when `Plastic::Graph::Work::Completion::Review.of(context).counting?` | finishes, exit 0; next: plastic intent end %{intent_id} | [`judge.rb:24`](../../../../lib/plastic/workflows/code/intent/judge.rb#L24) |
| `:judging` | otherwise | runs [Agent::Intent::Judge](#agentintentjudge) | [`judge.rb:26`](../../../../lib/plastic/workflows/code/intent/judge.rb#L26) |

It sets `problem`.

### Agent::Intent::Judge

The agent workflow `:agent_judge_intent`, in [`judge.rb:11`](../../../../lib/plastic/workflows/agent/intent/judge.rb#L11).

The agent reads the spec and the findings of every node, decides, and records the verdict.

![How Agent::Intent::Judge runs: its steps, where it stops, and its outcomes](agent_judge_intent.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| judge the delivery | agent step | `Plastic::Graph::Work::Completion::Review.of(context).counting?` | [`judge.rb:12`](../../../../lib/plastic/workflows/agent/intent/judge.rb#L12) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:handoff` | when a step is left | hands off, exit 0; next: plastic intent verdict %{intent_id} accept\|revise TEXT | [`judge.rb:19`](../../../../lib/plastic/workflows/agent/intent/judge.rb#L19) |
| `:done` | when every done check holds | finishes, exit 0; prints no next: line | [`judge.rb:21`](../../../../lib/plastic/workflows/agent/intent/judge.rb#L21) |

The agent step "judge the delivery" prints:

> Start a reasoning judge agent; the harness picks which kind. Tell it to read spec.md and the findings of every node, check each done criterion against the delivered work and decide: accept when every criterion holds, revise when something falls short. It records the verdict with plastic intent verdict %{intent_id} accept|revise TEXT. A revise starts a second review round, and a second revise stops the intent for the owner.

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| %{problem} | 1 | prints no next: line | [`judge.rb:21`](../../../../lib/plastic/workflows/code/intent/judge.rb#L21) |
| the judge's review round of intent %{intent_id} is used; the owner decides between abandoning the intent and a follow-up intent | 3 | prints no next: line | [`review_round.rb:11`](../../../../lib/plastic/workflows/review_round.rb#L11) |
| intent %{intent_id} is accepted | 0 | plastic intent end %{intent_id} | [`judge.rb:24`](../../../../lib/plastic/workflows/code/intent/judge.rb#L24) |
| the agent judges the delivery and records the verdict | 0 | plastic intent verdict %{intent_id} accept\|revise TEXT | [`judge.rb:19`](../../../../lib/plastic/workflows/agent/intent/judge.rb#L19) |
| the delivery is judged | 0 | prints no next: line | [`judge.rb:21`](../../../../lib/plastic/workflows/agent/intent/judge.rb#L21) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |
