# plastic graph ready

List the nodes ready to claim.

```sh
plastic graph ready ID
```

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ID` | the intent | |

## The events of one call, step by step

![The events of one call of plastic graph ready](events.svg)

The boxes on the left run in order. The boxes on the right are the ways the call stops or ends at that step.

## What one call changes

This command changes nothing.

The command is `Plastic::Commands::Graph::Ready`, in [`commands/graph/ready.rb`](../../../../lib/plastic/commands/graph/ready.rb).
