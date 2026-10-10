# plastic graph resume

Say where each named store's work stopped and what runs next.

Says where each named store's work stopped and what runs next. It reads the rows and writes nothing.

```sh
plastic graph resume [--stores LIST]
```

The command is `GraphResume`, in [`graph_resume.rb:13`](../../../../scripts/lib/plastic/commands/graph_resume.rb#L13). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `--stores LIST` | the stores to read, comma separated: registered projects or global; the call's own store when left out |  |

## What it touches

![What plastic graph resume touches](component.svg)

## Before the chain

The command's own `call`, at [`graph_resume.rb:19`](../../../../scripts/lib/plastic/commands/graph_resume.rb#L19), runs first:

```ruby
def call
  refuse_project
  offer_next(store_slugs.map { |slug| report(slug) }.each { |found| print_rows(found) })
end
```

## How the call flows

![The call of plastic graph resume](call.svg)

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| raise CLI::Command::Usage, "--stores names the stores; --project does not apply" if parsed[:stores] && parsed[:project] | 2 | prints no next: line | [`graph_resume.rb:31`](../../../../scripts/lib/plastic/commands/graph_resume.rb#L31) |
| raise CLI::Command::Usage, "name at least one store after --stores" if names.empty? | 2 | prints no next: line | [`graph_resume.rb:41`](../../../../scripts/lib/plastic/commands/graph_resume.rb#L41) |
| raise CLI::Command::Usage, "no registered project named #{name.inspect}; the projects are #{projects.keys.sort.join(", ")}" | 2 | prints no next: line | [`graph_resume.rb:50`](../../../../scripts/lib/plastic/commands/graph_resume.rb#L50) |
| return output.next_step("plastic status", because: "no store has open work") unless found | 0 | plastic status | [`graph_resume.rb:62`](../../../../scripts/lib/plastic/commands/graph_resume.rb#L62) |
| output.next_step(in_store(command, slug), because: reports.one? ? why : format(SEVERAL, slug)) | 0 | decided at run time | [`graph_resume.rb:70`](../../../../scripts/lib/plastic/commands/graph_resume.rb#L70) |
