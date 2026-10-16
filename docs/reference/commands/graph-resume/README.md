# plastic graph resume

Say where each named store's work stopped and what runs next.

```sh
plastic graph resume [--stores LIST]
```

The command is `Graph::Resume`, in [`resume.rb:14`](../../../../lib/plastic/commands/graph/resume.rb#L14). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `--stores LIST` | the stores to read, comma separated: registered projects or global; the call's own store when left out |  |

## What it touches

![What plastic graph resume touches](component.svg)

## The command

The command's `call`, at [`resume.rb:20`](../../../../lib/plastic/commands/graph/resume.rb#L20):

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
| Usage error: --stores names the stores; --project does not apply | 2 | prints no next: line | [`resume.rb:32`](../../../../lib/plastic/commands/graph/resume.rb#L32) |
| Usage error: name at least one store after --stores | 2 | prints no next: line | [`resume.rb:42`](../../../../lib/plastic/commands/graph/resume.rb#L42) |
| Usage error: no registered project named %{name}; the projects are %{projects} | 2 | prints no next: line | [`resume.rb:51`](../../../../lib/plastic/commands/graph/resume.rb#L51) |
| Offers the next command | 0 | plastic status | [`resume.rb:63`](../../../../lib/plastic/commands/graph/resume.rb#L63) |
| Offers the next command | 0 | decided at run time | [`resume.rb:71`](../../../../lib/plastic/commands/graph/resume.rb#L71) |
