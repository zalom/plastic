# plastic config list

List every setting with its value, globally or for one harness.

```sh
plastic config list [--harness NAME]
```

The command is `Config::List`, in [`list.rb:12`](../../../../lib/plastic/commands/config/list.rb#L12). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `--harness NAME` | the harness whose settings to use; the global settings when left out |  |

## What it touches

![What plastic config list touches](component.svg)

## The command

The command's `call`, at [`list.rb:15`](../../../../lib/plastic/commands/config/list.rb#L15):

```ruby
def call
  config.entries.each { |key, value| output.row(key, value.to_s) }
  output.next_step("plastic config set KEY VALUE#{harness_words}", because: "the settings are listed")
end
```

## How the call flows

![The call of plastic config list](call.svg)

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| Offers the next command | 0 | plastic config set KEY VALUE [HARNESS_WORDS] | [`list.rb:17`](../../../../lib/plastic/commands/config/list.rb#L17) |
