# plastic status

List every store's open and active intents, with node counts by state.

```sh
plastic status
```

The command is `Status`, in [`status.rb:12`](../../../../scripts/lib/plastic/commands/status.rb#L12). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

## What it touches

![What plastic status touches](component.svg)

## The command

The command's `call`, at [`status.rb:15`](../../../../scripts/lib/plastic/commands/status.rb#L15):

```ruby
def call
  projects = scope.projects
  shown = slugs.map { |slug| store_rows(slug, projects) }
  output.rows(shown.flat_map(&:first))
  offer_next(shown.filter_map(&:last).first)
end
```

## How the call flows

![The call of plastic status](call.svg)

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| Offers the next command | 0 | plastic next | [`status.rb:27`](../../../../scripts/lib/plastic/commands/status.rb#L27) |
| Offers the next command | 0 | decided at run time | [`status.rb:29`](../../../../scripts/lib/plastic/commands/status.rb#L29) |
