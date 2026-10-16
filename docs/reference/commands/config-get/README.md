# plastic config get

Print the value of one setting.

```sh
plastic config get KEY [--harness NAME]
```

The command is `Config::Get`, in [`get.rb:11`](../../../../lib/plastic/commands/config/get.rb#L11). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `KEY` | the setting, as its dotted name | |
| `--harness NAME` | the harness whose settings to use; the global settings when left out |  |

## Components

![The components on the path of plastic config get](component.svg)

The figure shows the command, the workflows it runs, the classes behind them, and the databases and files they reach.

## The events of one call

![The call of plastic config get](call.svg)

The command's `call`, at [`get.rb:16`](../../../../lib/plastic/commands/config/get.rb#L16):

```ruby
def call
  key = parsed[:key]
  output.row(key, current(key).to_s)
  output.next_step("plastic config set #{key} VALUE#{harness_words}", because: "the setting is printed")
end
```

Its steps run in this order:

1. `key = parsed[:key]` [`get.rb:17`](../../../../lib/plastic/commands/config/get.rb#L17)
2. `output.row(key, current(key).to_s)` [`get.rb:18`](../../../../lib/plastic/commands/config/get.rb#L18)
3. `output.next_step("plastic config set #{key} VALUE#{harness_words}", because: "the setting is printed")` [`get.rb:19`](../../../../lib/plastic/commands/config/get.rb#L19)

## What one call reads, writes and prints

![What one call of plastic config get reads, writes and prints](touches.svg)

It reads and writes no store database and prints no store file.

## How a call ends

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| Offers the next command | 0 | plastic config set KEY VALUE [HARNESS_WORDS] | [`get.rb:19`](../../../../lib/plastic/commands/config/get.rb#L19) |

## What the page leaves out

Every call shares a few things that this page does not repeat; [the command DSL](../../dsl/README.md#what-every-call-shares) names them.

- No gate of this command refuses, so exit 3 never happens.
