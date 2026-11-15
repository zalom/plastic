# plastic config list

List every setting with its value, globally or for one harness.

```sh
plastic config list [--harness NAME]
```

The command is `Config::List`, in [`list.rb:12`](../../../../lib/plastic/commands/config/list.rb#L12). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `--harness NAME` | the harness whose settings to use; the global settings when left out |  |

## Components

![The components on the path of plastic config list](component.svg)

The figure shows the command, the workflows it runs, the classes behind them, and the databases and files they reach.

## The events of one call

The call starts the workflow `Code::Config::List`, in [`list.rb:12`](../../../../lib/plastic/workflows/code/config/list.rb#L12).

Lists every setting with its value: the global settings, or those of one harness with --harness. It writes nothing.

![How Code::Config::List runs: its steps, where it stops, and its outcomes](code_list_config.svg)

Its rows run in this order:

1. Read: print each setting with its value. [`list.rb:17`](../../../../lib/plastic/workflows/code/config/list.rb#L17)
2. Outcome `:done`, always: finishes with exit 0; next: plastic config set KEY VALUEHARNESS_WORDS. [`list.rb:23`](../../../../lib/plastic/workflows/code/config/list.rb#L23)

It sets `harness_words`.

In the words of workflow engines, the rows are these four parts:

- **Trigger**: the call starts the workflow `Code::Config::List`.
- **Activities**: 1 read.
- **Transitions**: .
- **Outcomes**: `:done` ends the call.

## What one call reads, writes and prints

![What one call of plastic config list reads, writes and prints](touches.svg)

It reads and writes no store database and prints no store file.

## How a call ends

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| the settings are listed | 0 | plastic config set KEY VALUEHARNESS_WORDS | [`list.rb:23`](../../../../lib/plastic/workflows/code/config/list.rb#L23) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:108`](../../../../lib/plastic/code_workflow.rb#L108) |

## What the page leaves out

Every call shares a few things that this page does not repeat; [the command DSL](../../dsl/README.md#what-every-call-shares) names them.

- No gate of this command refuses, so exit 3 never happens.
