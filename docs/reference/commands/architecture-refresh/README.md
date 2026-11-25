# plastic architecture refresh

Tell the agent to regenerate the architecture map with its own tool.

```sh
plastic architecture refresh
```

## The events of one call, step by step

![The events of one call of plastic architecture refresh](events.svg)

The boxes on the left run in order. The boxes on the right are the ways the call stops or ends at that step.

## What one call changes

This command changes nothing.

## What the agent workflow steps print

| Step | The text the agent gets |
| --- | --- |
| 1 | Regenerate the project's architecture map with an architecture mapping tool such as Enola; the choice of tool is yours. Read the new map for context, together with the project's AGENTS.md, before you plan code work. Plastic runs no tool and asks for no record of the map. |

The command is `Plastic::Commands::Architecture::Refresh`, in [`commands/architecture/refresh.rb`](../../../../lib/plastic/commands/architecture/refresh.rb).
