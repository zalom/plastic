# plastic intent show

Print one intent's status, criteria, decisions, rulings and nodes.

```sh
plastic intent show ID
```

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ID` | the intent | |

## The events of one call, step by step

![The events of one call of plastic intent show](events.svg)

The boxes on the left run in order. The boxes on the right are the ways the call stops or ends at that step.

## What one call changes

This command changes nothing.

The command is `Plastic::Commands::Intent::Show`, in [`show.rb:10`](../../../../lib/plastic/commands/intent/show.rb#L10).
