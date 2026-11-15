# plastic graph show

Print every node and edge of an intent.

Prints one intent's nodes and edges from the rows. It reads and writes nothing.

```sh
plastic graph show ID
```

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ID` | the intent | |

## The events of one call, step by step

![The events of one call of plastic graph show](events.svg)

The boxes on the left run in order. The boxes on the right are the ways the call stops or ends at that step.

## What one call changes

This command changes nothing.

The command is `Plastic::Commands::Graph::Show`, in [`show.rb:9`](../../../../lib/plastic/commands/graph/show.rb#L9).
