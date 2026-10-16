# plastic architecture refresh

Tell the agent to regenerate the architecture map with its own tool.

```sh
plastic architecture refresh
```

The command is `Architecture::Refresh`, in [`refresh.rb:9`](../../../../lib/plastic/commands/architecture/refresh.rb#L9). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

## Components

![The components on the path of plastic architecture refresh](component.svg)

The figure shows the command, the workflows it runs, the classes behind them, and the databases and files they reach.

## The events of one call

The call starts the workflow `Agent::Architecture::Refresh`, in [`refresh.rb:11`](../../../../lib/plastic/workflows/agent/architecture/refresh.rb#L11).

The agent regenerates the architecture map with the tool it chose. Plastic runs no tool and reads no result, so the step is never done on its own.

![How Agent::Architecture::Refresh runs: its steps, where it stops, and its outcomes](agent_refresh_architecture.svg)

Its rows run in this order:

1. Agent step: refresh the architecture map. Runs on every call; its done check is `false`. The call prints its `say:` text. [`refresh.rb:12`](../../../../lib/plastic/workflows/agent/architecture/refresh.rb#L12)
2. Outcome `:handoff`, when a step is left: hands off with exit 0; prints no next: line. [`refresh.rb:17`](../../../../lib/plastic/workflows/agent/architecture/refresh.rb#L17)
3. Outcome `:done`, when every done check holds: finishes with exit 0; prints no next: line. [`refresh.rb:18`](../../../../lib/plastic/workflows/agent/architecture/refresh.rb#L18)

The agent step "refresh the architecture map" prints:

> Regenerate the project's architecture map with an architecture mapping tool such as Enola; the choice of tool is yours. Read the new map for context. When you deliver an intent, note the tool, the source revision the map describes, what it covers and what it leaves out as the Architecture map: line under Verification in outcome.md.

While a step is left, the call hands off with exit 0 from `:handoff`: it prints the `say:` text of each failing step and prints no next: line. The command writes nothing, so the call keeps no routine run row. The next call starts fresh and checks the steps again.

In the words of workflow engines, the rows are these four parts:

- **Trigger**: the call starts the workflow `Agent::Architecture::Refresh`.
- **Activities**: 1 agent step.
- **Transitions**: a step runs only while its done check fails.
- **Outcomes**: `:handoff`, `:done` end the call.

## What one call reads, writes and prints

![What one call of plastic architecture refresh reads, writes and prints](touches.svg)

It reads and writes no store database and prints no store file.

A second call runs the same rows again. A step runs again only when its done check fails.

| Step | Done when | The second call | Code |
| --- | --- | --- | --- |
| refresh the architecture map | `false` | runs it again | [`refresh.rb:12`](../../../../lib/plastic/workflows/agent/architecture/refresh.rb#L12) |

## How a call ends

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| the agent refreshes the architecture map with its own tool | 0 | prints no next: line | [`refresh.rb:17`](../../../../lib/plastic/workflows/agent/architecture/refresh.rb#L17) |
| the architecture map was refreshed | 0 | prints no next: line | [`refresh.rb:18`](../../../../lib/plastic/workflows/agent/architecture/refresh.rb#L18) |

## What the page leaves out

Every call shares a few things that this page does not repeat; [the command DSL](../../dsl/README.md#what-every-call-shares) names them.

- No gate of this command refuses, so exit 3 never happens.
