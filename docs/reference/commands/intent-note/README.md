# plastic intent note

Add one line under Notes in the outcome of an intent, keeping the earlier text as a revision.

```sh
plastic intent note ID TEXT [--kind KIND]
```

The command is `Intent::Note`, in [`note.rb:11`](../../../../lib/plastic/commands/intent/note.rb#L11). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ID` | the intent | |
| `TEXT` | the note, one line | |
| `--kind KIND` | Review, Commit or Report | `"Report"` |

## What it touches

![What plastic intent note touches](component.svg)

## Before the chain

The command's own `call`, at [`note.rb:19`](../../../../lib/plastic/commands/intent/note.rb#L19), runs first:

```ruby
def call
  kinds = Plastic::Graph::Knowledge::Intent::Notes::KINDS
  raise CLI::Command::Usage, "KIND takes #{kinds.join(", ")}" unless kinds.include?(parsed[:kind])

  super
end
```

## How the call flows

![The chain of workflows that plastic intent note runs](chain.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [Code::Intent::Note](#codeintentnote) | code | [`note.rb:10`](../../../../lib/plastic/workflows/code/intent/note.rb#L10) |

### Code::Intent::Note

The code workflow `:code_note_intent`, in [`note.rb:10`](../../../../lib/plastic/workflows/code/intent/note.rb#L10).

Adds a note line to the outcome of an intent.

![How Code::Intent::Note runs: its steps, where it stops, and its outcomes](code_note_intent.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| find the intent | read |  | [`note.rb:15`](../../../../lib/plastic/workflows/code/intent/note.rb#L15) |
| no intent %{intent_id} in this store | gate, stops with exit 1 | `!context.intent.nil?` | [`note.rb:19`](../../../../lib/plastic/workflows/code/intent/note.rb#L19) |
| check the note | read |  | [`note.rb:21`](../../../../lib/plastic/workflows/code/intent/note.rb#L21) |
| %{problem} | gate, stops with exit 1 | `context.problem.nil?` | [`note.rb:25`](../../../../lib/plastic/workflows/code/intent/note.rb#L25) |
| write the note | step | `!context.reference.nil?` | [`note.rb:27`](../../../../lib/plastic/workflows/code/intent/note.rb#L27) |
| say what was written | read |  | [`note.rb:31`](../../../../lib/plastic/workflows/code/intent/note.rb#L31) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:done` | always | finishes, exit 0; prints no next: line | [`note.rb:35`](../../../../lib/plastic/workflows/code/intent/note.rb#L35) |

It sets `intent`, `problem`, `reference`.

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| no intent %{intent_id} in this store | 1 | prints no next: line | [`note.rb:19`](../../../../lib/plastic/workflows/code/intent/note.rb#L19) |
| %{problem} | 1 | prints no next: line | [`note.rb:25`](../../../../lib/plastic/workflows/code/intent/note.rb#L25) |
| the outcome holds the note | 0 | prints no next: line | [`note.rb:35`](../../../../lib/plastic/workflows/code/intent/note.rb#L35) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |
| Usage error: KIND takes %{kinds} | 2 | prints no next: line | [`note.rb:21`](../../../../lib/plastic/commands/intent/note.rb#L21) |
