# plastic status

List every store's intents by group, with node counts by state.

```sh
plastic status
```

## The events of one call, step by step

![The events of one call of plastic status](events.svg)

The boxes on the left run in order. The boxes on the right are the ways the call stops or ends at that step.

## What one call changes

This command changes nothing.

The command is `Plastic::Commands::Status`, in [`status.rb:14`](../../../../lib/plastic/commands/status.rb#L14).
