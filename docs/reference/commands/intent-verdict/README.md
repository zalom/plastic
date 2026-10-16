# plastic intent verdict

Record the verdict of the next review round of an intent.

```sh
plastic intent verdict ID accept|revise TEXT
```

The command is `Intent::Verdict`, in [`verdict.rb:9`](../../../../lib/plastic/commands/intent/verdict.rb#L9). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ID` | the intent | |
| `accept|revise` | the verdict of this review round | |
| `TEXT` | what the review showed | |

## What it touches

![What plastic intent verdict touches](component.svg)

## Before the chain

The command's own `call`, at [`verdict.rb:23`](../../../../lib/plastic/commands/intent/verdict.rb#L23), runs first:

```ruby
def call(*)
  raise CLI::Command::Usage, "the verdict takes accept or revise" unless VERDICTS.include?(parsed[:verdict])

  super
end
```

## How the call flows

![The chain of workflows that plastic intent verdict runs](chain.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [Code::Intent::Verdict::Prepare](#codeintentverdictprepare) | code | [`prepare.rb:13`](../../../../lib/plastic/workflows/code/intent/verdict/prepare.rb#L13) |
| [Code::Intent::Verdict](#codeintentverdict) | code | [`verdict.rb:13`](../../../../lib/plastic/workflows/code/intent/verdict.rb#L13) |

### Code::Intent::Verdict::Prepare

The code workflow `:code_prepare_verdict`, in [`prepare.rb:13`](../../../../lib/plastic/workflows/code/intent/verdict/prepare.rb#L13).

Reads the intent and its judge rounds before a verdict is written: a missing or closed intent fails, both rounds used is the owner's step.

![How Code::Intent::Verdict::Prepare runs: its steps, where it stops, and its outcomes](code_prepare_verdict.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| check the intent | read |  | [`prepare.rb:16`](../../../../lib/plastic/workflows/code/intent/verdict/prepare.rb#L16) |
| %{problem} | gate, stops with exit 1 | `context.problem.nil?` | [`prepare.rb:20`](../../../../lib/plastic/workflows/code/intent/verdict/prepare.rb#L20) |
| the judge's review round of intent %{intent_id} is used; the owner decides between abandoning the intent and a follow-up intent | gate, stops with exit 3 | `context.work.rounds_left?(context.intent_id)` | [`prepare.rb:21`](../../../../lib/plastic/workflows/code/intent/verdict/prepare.rb#L21) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:recording` | always | runs [Code::Intent::Verdict](#codeintentverdict) | [`prepare.rb:24`](../../../../lib/plastic/workflows/code/intent/verdict/prepare.rb#L24) |

It sets `problem`.

### Code::Intent::Verdict

The code workflow `:code_record_verdict`, in [`verdict.rb:13`](../../../../lib/plastic/workflows/code/intent/verdict.rb#L13).

Writes the verdict row of the next review round. A second revise ends the call as the owner's step.

![How Code::Intent::Verdict runs: its steps, where it stops, and its outcomes](code_record_verdict.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| count the rounds written so far | read |  | [`verdict.rb:18`](../../../../lib/plastic/workflows/code/intent/verdict.rb#L18) |
| write the verdict | step | `rounds(context) > context.rounds_before` | [`verdict.rb:20`](../../../../lib/plastic/workflows/code/intent/verdict.rb#L20) |
| the judge's review round of intent %{intent_id} is used; the owner decides between abandoning the intent and a follow-up intent | gate, stops with exit 3 | `!Graph::Work::Completion::Review.of(context).used_up?` | [`review_round.rb:11`](../../../../lib/plastic/workflows/review_round.rb#L11) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:revise` | when `latest(context).verdict == "revise"` | finishes, exit 0; next: plastic node add %{intent_id} TITLE --criterion KEY | [`verdict.rb:31`](../../../../lib/plastic/workflows/code/intent/verdict.rb#L31) |
| `:accepted` | otherwise | finishes, exit 0; next: plastic intent end %{intent_id} | [`verdict.rb:33`](../../../../lib/plastic/workflows/code/intent/verdict.rb#L33) |

It sets `rounds_before`.

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| %{problem} | 1 | prints no next: line | [`prepare.rb:20`](../../../../lib/plastic/workflows/code/intent/verdict/prepare.rb#L20) |
| the judge's review round of intent %{intent_id} is used; the owner decides between abandoning the intent and a follow-up intent | 3 | prints no next: line | [`prepare.rb:21`](../../../../lib/plastic/workflows/code/intent/verdict/prepare.rb#L21) |
| the judge's review round of intent %{intent_id} is used; the owner decides between abandoning the intent and a follow-up intent | 3 | prints no next: line | [`review_round.rb:11`](../../../../lib/plastic/workflows/review_round.rb#L11) |
| the judge asked for a revision; add a node that fixes it | 0 | plastic node add %{intent_id} TITLE --criterion KEY | [`verdict.rb:31`](../../../../lib/plastic/workflows/code/intent/verdict.rb#L31) |
| intent %{intent_id} is accepted | 0 | plastic intent end %{intent_id} | [`verdict.rb:33`](../../../../lib/plastic/workflows/code/intent/verdict.rb#L33) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |
| Usage error: the verdict takes accept or revise | 2 | prints no next: line | [`verdict.rb:24`](../../../../lib/plastic/commands/intent/verdict.rb#L24) |
