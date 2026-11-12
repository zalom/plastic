# plastic intent link

Write a typed link from an intent to a ref.

Writes one `links` row from ID to TARGET: an intent id, a ruling ref such as `1/D1`, or a ref with a store prefix such as `global:25`.

```sh
plastic intent link ID KIND TARGET
```

The command is `Intent::Link`, in [`link.rb:11`](../../../../lib/plastic/commands/intent/link.rb#L11). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ID` | the intent this link starts from | |
| `KIND` | cites, supersedes, answers, source or chain | |
| `TARGET` | an intent, a ruling, or a ref with a store prefix | |

## What it touches

![What plastic intent link touches](component.svg)

## Before the chain

The command's own `call`, at [`link.rb:20`](../../../../lib/plastic/commands/intent/link.rb#L20), runs first:

```ruby
def call
  raise CLI::Command::Usage, "KIND takes #{Plastic::Graph::Knowledge::Link::KINDS.join(", ")}" unless Plastic::Graph::Knowledge::Link::KINDS.include?(parsed[:kind])

  super
end
```

## How the call flows

![The chain of workflows that plastic intent link runs](chain.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [Code::Intent::Link](#codeintentlink) | code | [`link.rb:11`](../../../../lib/plastic/workflows/code/intent/link.rb#L11) |

### Code::Intent::Link

The code workflow `:code_add_link`, in [`link.rb:11`](../../../../lib/plastic/workflows/code/intent/link.rb#L11).

Writes one guarded link: failed on a missing id or target, refused on a self link or a link already there.

![How Code::Intent::Link runs: its steps, where it stops, and its outcomes](code_add_link.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| check the ends | read |  | [`link.rb:16`](../../../../lib/plastic/workflows/code/intent/link.rb#L16) |
| %{problem} | gate, stops with exit 1 | `context.problem.nil?` | [`link.rb:20`](../../../../lib/plastic/workflows/code/intent/link.rb#L20) |
| check for a self link or a repeat | read |  | [`link.rb:22`](../../../../lib/plastic/workflows/code/intent/link.rb#L22) |
| %{refusal} | gate, stops with exit 3 | `context.refusal.nil?` | [`link.rb:26`](../../../../lib/plastic/workflows/code/intent/link.rb#L26) |
| add the link | step | `!context.added.nil?` | [`link.rb:28`](../../../../lib/plastic/workflows/code/intent/link.rb#L28) |
| say what was written | read |  | [`link.rb:32`](../../../../lib/plastic/workflows/code/intent/link.rb#L32) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:done` | always | finishes, exit 0; next: plastic sync down | [`link.rb:36`](../../../../lib/plastic/workflows/code/intent/link.rb#L36) |

It sets `problem`, `refusal`, `added`.

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| %{problem} | 1 | prints no next: line | [`link.rb:20`](../../../../lib/plastic/workflows/code/intent/link.rb#L20) |
| %{refusal} | 3 | prints no next: line | [`link.rb:26`](../../../../lib/plastic/workflows/code/intent/link.rb#L26) |
| the link is on record | 0 | plastic sync down | [`link.rb:36`](../../../../lib/plastic/workflows/code/intent/link.rb#L36) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |
| Usage error: KIND takes %{lastic} | 2 | prints no next: line | [`link.rb:21`](../../../../lib/plastic/commands/intent/link.rb#L21) |
