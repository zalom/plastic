# plastic project links

List the links that name an intent or a ruling this store lacks.

```sh
plastic project links
```

The command is `Project::Links`, in [`links.rb:13`](../../../../lib/plastic/commands/project/links.rb#L13). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

## What it touches

![What plastic project links touches](component.svg)

## The command

The command's `call`, at [`links.rb:16`](../../../../lib/plastic/commands/project/links.rb#L16):

```ruby
def call
  broken = broken_links
  broken.each { |link| output.raw("#{link.from_ref} #{link.kind} #{link.to_ref}") }
  output.raw(Plastic::Graph::Knowledge::Link::Check.summary(broken.size)) if broken.any?
  output.next_step("plastic status", because: "every link names an intent or a ruling this store holds")
end
```

## How the call flows

![The call of plastic project links](call.svg)

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| Offers the next command | 0 | plastic status | [`links.rb:20`](../../../../lib/plastic/commands/project/links.rb#L20) |
