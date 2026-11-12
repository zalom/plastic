# plastic config

Pick which on/off settings are on, on the choice screen.

Shows the on/off settings on the choice screen, the ones that are on already picked, and writes each one the person changed. See docs/help/choice-screen.md.

```sh
plastic config [ANSWER] [--harness NAME]
```

The command is `Config`, in [`config.rb:12`](../../../../lib/plastic/commands/config.rb#L12). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ANSWER` | the person's answer to the numbered list | |
| `--harness NAME` | the harness whose settings to use; the global settings when left out |  |

## Components

![The components on the path of plastic config](component.svg)

The figure shows the command, the workflows it runs, the classes behind them, and the databases and files they reach.

## The events of one call

![The call of plastic config](call.svg)

The command's `call`, at [`config.rb:23`](../../../../lib/plastic/commands/config.rb#L23):

```ruby
def call
  result = pick(choices)
  save(result.labels) if result.is_a?(CLI::Screen::Chosen)
  output.next_step("plastic config list#{harness_words}", because: "the person left with no change") if result.is_a?(CLI::Screen::Left)
end
```

Its steps run in this order:

1. `result = pick(choices)` [`config.rb:24`](../../../../lib/plastic/commands/config.rb#L24)
2. `save(result.labels) if result.is_a?(CLI::Screen::Chosen)` [`config.rb:25`](../../../../lib/plastic/commands/config.rb#L25)
3. `output.next_step("plastic config list#{harness_words}", because: "the person left with no change") if result.is_a?(CLI::Screen::Left)` [`config.rb:26`](../../../../lib/plastic/commands/config.rb#L26)

## What one call reads, writes and prints

![What one call of plastic config reads, writes and prints](touches.svg)

It reads and writes no store database and prints no store file.

## How a call ends

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| Offers the next command | 0 | plastic config list [HARNESS_WORDS] | [`config.rb:26`](../../../../lib/plastic/commands/config.rb#L26) |
| Offers the next command | 0 | plastic config list [HARNESS_WORDS] | [`config.rb:45`](../../../../lib/plastic/commands/config.rb#L45) |

## What the page leaves out

Every call shares a few things that this page does not repeat; [the command DSL](../../dsl/README.md#what-every-call-shares) names them.

- No gate of this command refuses, so exit 3 never happens.
