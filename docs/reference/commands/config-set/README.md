# plastic config set

Write one setting to config.yml, globally or for one harness.

```sh
plastic config set KEY VALUE [--harness NAME]
```

The command is `Config::Set`, in [`set.rb:13`](../../../../lib/plastic/commands/config/set.rb#L13). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `KEY` | the setting, as its dotted name | |
| `VALUE` | the new value | |
| `--harness NAME` | the harness whose settings to use; the global settings when left out |  |

## What it touches

![What plastic config set touches](component.svg)

## The command

The command's `call`, at [`set.rb:28`](../../../../lib/plastic/commands/config/set.rb#L28):

```ruby
def call
  key = parsed[:key]
  value = checked(key, self.class.scalar(parsed[:value]))
  config.set(key, value)
  output.row(key, value.to_s)
  output.next_step("plastic config get #{key}#{harness_words}", because: "the setting is written")
end
```

## How the call flows

![The call of plastic config set](call.svg)

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| Usage error: a setting takes one value, not %{text} | 2 | prints no next: line | [`set.rb:21`](../../../../lib/plastic/commands/config/set.rb#L21) |
| Usage error: %{key} takes true or false | 2 | prints no next: line | [`set.rb:40`](../../../../lib/plastic/commands/config/set.rb#L40) |
| Offers the next command | 0 | plastic config get KEY [HARNESS_WORDS] | [`set.rb:33`](../../../../lib/plastic/commands/config/set.rb#L33) |
