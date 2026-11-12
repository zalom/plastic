# plastic intent end

Close a delivered intent once its verdict, nodes and outcome allow it, or print what is missing.

```sh
plastic intent end ID
```

The command is `Intent::End`, in [`end.rb:9`](../../../../lib/plastic/commands/intent/end.rb#L9). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ID` | the intent | |

## What it touches

![What plastic intent end touches](component.svg)

## How the call flows

![The chain of workflows that plastic intent end runs](chain.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [Code::Intent::End::Prepare](#codeintentendprepare) | code | [`prepare.rb:17`](../../../../lib/plastic/workflows/code/intent/end/prepare.rb#L17) |
| [Agent::Intent::End](#agentintentend) | agent | [`end.rb:10`](../../../../lib/plastic/workflows/agent/intent/end.rb#L10) |
| [Agent::Intent::End::CheckMerge](#agentintentendcheckmerge) | agent | [`check_merge.rb:14`](../../../../lib/plastic/workflows/agent/intent/end/check_merge.rb#L14) |
| [Code::Intent::End](#codeintentend) | code | [`end.rb:10`](../../../../lib/plastic/workflows/code/intent/end.rb#L10) |
| [Agent::Shared::WindDownIntent](#agentsharedwinddownintent) | agent | [`wind_down_intent.rb:10`](../../../../lib/plastic/workflows/agent/shared/wind_down_intent.rb#L10) |

### Code::Intent::End::Prepare

The code workflow `:code_prepare_ending`, in [`prepare.rb:17`](../../../../lib/plastic/workflows/code/intent/end/prepare.rb#L17).

Reads what closing an intent needs: the rows, the judge's verdict, outcome.md and, by the review setting, the pull request.

![How Code::Intent::End::Prepare runs: its steps, where it stops, and its outcomes](code_prepare_ending.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| read the intent | read |  | [`prepare.rb:20`](../../../../lib/plastic/workflows/code/intent/end/prepare.rb#L20) |
| no intent %{intent_id} in this store | gate, stops with exit 1 | `!context.intent.nil?` | [`prepare.rb:25`](../../../../lib/plastic/workflows/code/intent/end/prepare.rb#L25) |
| intent %{intent_id} is not open or active | gate, stops with exit 1 | `context.closed \|\| %w[open active].include?(context.intent.status)` | [`prepare.rb:26`](../../../../lib/plastic/workflows/code/intent/end/prepare.rb#L26) |
| check delivery ownership | read |  | [`prepare.rb:29`](../../../../lib/plastic/workflows/code/intent/end/prepare.rb#L29) |
| %{problem} | gate, stops with exit 3 | `context.problem.nil?` | [`prepare.rb:33`](../../../../lib/plastic/workflows/code/intent/end/prepare.rb#L33) |
| check the completion records | read |  | [`prepare.rb:35`](../../../../lib/plastic/workflows/code/intent/end/prepare.rb#L35) |
| the judge's review round of intent %{intent_id} is used; the owner decides between abandoning the intent and a follow-up intent | gate, stops with exit 3 | `!context.used_up` | [`prepare.rb:77`](../../../../lib/plastic/workflows/code/intent/end/prepare.rb#L77) |
| the pull request of intent %{intent_id} waits for the person's approval; add the line Approved: to the Verification section of outcome.md once they approve, then run plastic sync up | gate, stops with exit 3 | `!context.awaiting_approval` | [`prepare.rb:79`](../../../../lib/plastic/workflows/code/intent/end/prepare.rb#L79) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:closed` | when `context.closed` | finishes, exit 0; next: plastic next | [`prepare.rb:84`](../../../../lib/plastic/workflows/code/intent/end/prepare.rb#L84) |
| `:agent_needed` | when `!context.requirements.empty? \|\| !context.judged` | runs [Agent::Intent::End](#agentintentend) | [`prepare.rb:86`](../../../../lib/plastic/workflows/code/intent/end/prepare.rb#L86) |
| `:unverified` | when `!verified?(context)` | runs [Agent::Intent::End::CheckMerge](#agentintentendcheckmerge) | [`prepare.rb:87`](../../../../lib/plastic/workflows/code/intent/end/prepare.rb#L87) |
| `:ready` | otherwise | runs [Code::Intent::End](#codeintentend) | [`prepare.rb:88`](../../../../lib/plastic/workflows/code/intent/end/prepare.rb#L88) |

It sets `intent`, `closed`, `problem`, `requirements`, `judged`, `used_up`, `awaiting_approval`, `intent_folder`, `merge_recorded`, `map_recorded`, `missing`.

### Agent::Intent::End

The agent workflow `:agent_finish_intent`, in [`end.rb:10`](../../../../lib/plastic/workflows/agent/intent/end.rb#L10).

The harness writes the records the close needs and has the work judged.

![How Agent::Intent::End runs: its steps, where it stops, and its outcomes](agent_finish_intent.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| finish the required records | agent step | `context.requirements.empty?` | [`end.rb:11`](../../../../lib/plastic/workflows/agent/intent/end.rb#L11) |
| have the delivery judged | agent step | `context.judged` | [`end.rb:13`](../../../../lib/plastic/workflows/agent/intent/end.rb#L13) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:handoff` | when a step is left | hands off, exit 0; prints no next: line | [`end.rb:17`](../../../../lib/plastic/workflows/agent/intent/end.rb#L17) |
| `:done` | when every done check holds | finishes, exit 0; prints no next: line | [`end.rb:18`](../../../../lib/plastic/workflows/agent/intent/end.rb#L18) |

The agent step "finish the required records" prints:

> Complete these recorded prerequisites: %{requirements}

The agent step "have the delivery judged" prints:

> No accepted review counts yet. Run plastic intent judge %{intent_id}; the judge records the verdict of the next review round with plastic intent verdict. Then run plastic intent end %{intent_id} again.

### Agent::Intent::End::CheckMerge

The agent workflow `:agent_check_merge`, in [`check_merge.rb:14`](../../../../lib/plastic/workflows/agent/intent/end/check_merge.rb#L14).

The agent checks that the code is merged and confirms the architecture map, then records both under Verification in outcome.md. Plastic runs no version control command and records what the agent writes.

![How Agent::Intent::End::CheckMerge runs: its steps, where it stops, and its outcomes](agent_check_merge.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| check the code is merged | agent step | `context.merge_recorded` | [`check_merge.rb:15`](../../../../lib/plastic/workflows/agent/intent/end/check_merge.rb#L15) |
| confirm the architecture map | agent step | `context.map_recorded` | [`check_merge.rb:19`](../../../../lib/plastic/workflows/agent/intent/end/check_merge.rb#L19) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:handoff` | when a step is left | hands off, exit 0; prints no next: line | [`check_merge.rb:25`](../../../../lib/plastic/workflows/agent/intent/end/check_merge.rb#L25) |
| `:done` | when every done check holds | finishes, exit 0; prints no next: line | [`check_merge.rb:26`](../../../../lib/plastic/workflows/agent/intent/end/check_merge.rb#L26) |

The agent step "check the code is merged" prints:

> Check with your own version control tool that the intent's branch is merged into its base. Then add the line '- Merged: <branch> into <base> at <commit or pull request>' under ## Verification in %{intent_folder}/outcome.md. Plastic runs no version control command; it records what you write.

The agent step "confirm the architecture map" prints:

> Now that the work is delivered, fetch the architecture map once more, with the tool you used before planning or by mapping the code yourself, and confirm that it describes the delivered code. Then add the line '- Architecture map: <tool> at <source revision>' under ## Verification in %{intent_folder}/outcome.md. Run plastic sync up and then plastic intent end %{intent_id} again.

### Code::Intent::End

The code workflow `:code_close_intent`, in [`end.rb:10`](../../../../lib/plastic/workflows/code/intent/end.rb#L10).

Closure can be retried after the work commit but before lock cleanup. The files of the intent print after the close.

![How Code::Intent::End runs: its steps, where it stops, and its outcomes](code_close_intent.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| check cleanup again | read |  | [`end.rb:13`](../../../../lib/plastic/workflows/code/intent/end.rb#L13) |
| close the intent and finish cleanup | step | `context.ended == true` | [`end.rb:15`](../../../../lib/plastic/workflows/code/intent/end.rb#L15) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:done` | always | runs [Agent::Shared::WindDownIntent](#agentsharedwinddownintent) | [`end.rb:21`](../../../../lib/plastic/workflows/code/intent/end.rb#L21) |

It sets `ended`.

### Agent::Shared::WindDownIntent

The agent workflow `:agent_wind_down_intent`, in [`wind_down_intent.rb:10`](../../../../lib/plastic/workflows/agent/shared/wind_down_intent.rb#L10).

The agent stops what the intent started. Plastic runs and stops nothing.

![How Agent::Shared::WindDownIntent runs: its steps, where it stops, and its outcomes](agent_wind_down_intent.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| stop what intent %{intent_id} started | agent step | `false` | [`wind_down_intent.rb:11`](../../../../lib/plastic/workflows/agent/shared/wind_down_intent.rb#L11) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:handoff` | when a step is left | hands off, exit 0; prints no next: line | [`wind_down_intent.rb:15`](../../../../lib/plastic/workflows/agent/shared/wind_down_intent.rb#L15) |
| `:done` | when every done check holds | finishes, exit 0; prints no next: line | [`wind_down_intent.rb:16`](../../../../lib/plastic/workflows/agent/shared/wind_down_intent.rb#L16) |

The agent step "stop what intent %{intent_id} started" prints:

> Stop the processes and the agents that intent %{intent_id} started: servers, watchers, background jobs and subagents. Plastic runs none of them and stops none of them.

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| no intent %{intent_id} in this store | 1 | prints no next: line | [`prepare.rb:25`](../../../../lib/plastic/workflows/code/intent/end/prepare.rb#L25) |
| intent %{intent_id} is not open or active | 1 | prints no next: line | [`prepare.rb:26`](../../../../lib/plastic/workflows/code/intent/end/prepare.rb#L26) |
| %{problem} | 3 | prints no next: line | [`prepare.rb:33`](../../../../lib/plastic/workflows/code/intent/end/prepare.rb#L33) |
| the judge's review round of intent %{intent_id} is used; the owner decides between abandoning the intent and a follow-up intent | 3 | prints no next: line | [`prepare.rb:77`](../../../../lib/plastic/workflows/code/intent/end/prepare.rb#L77) |
| the pull request of intent %{intent_id} waits for the person's approval; add the line Approved: to the Verification section of outcome.md once they approve, then run plastic sync up | 3 | prints no next: line | [`prepare.rb:79`](../../../../lib/plastic/workflows/code/intent/end/prepare.rb#L79) |
| intent %{intent_id} is already done | 0 | plastic next | [`prepare.rb:84`](../../../../lib/plastic/workflows/code/intent/end/prepare.rb#L84) |
| intent %{intent_id} cannot end yet. %{missing} | 0 | prints no next: line | [`end.rb:17`](../../../../lib/plastic/workflows/agent/intent/end.rb#L17) |
| the completion records are ready | 0 | prints no next: line | [`end.rb:18`](../../../../lib/plastic/workflows/agent/intent/end.rb#L18) |
| the agent checks the merge and the architecture map and records both in outcome.md | 0 | prints no next: line | [`check_merge.rb:25`](../../../../lib/plastic/workflows/agent/intent/end/check_merge.rb#L25) |
| the merge and the architecture map are recorded | 0 | prints no next: line | [`check_merge.rb:26`](../../../../lib/plastic/workflows/agent/intent/end/check_merge.rb#L26) |
| the agent stops the processes and agents the intent started | 0 | prints no next: line | [`wind_down_intent.rb:15`](../../../../lib/plastic/workflows/agent/shared/wind_down_intent.rb#L15) |
| nothing the intent started is left running | 0 | prints no next: line | [`wind_down_intent.rb:16`](../../../../lib/plastic/workflows/agent/shared/wind_down_intent.rb#L16) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |
