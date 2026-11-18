# plastic intent spec

Print the grilling method, how done criteria are written, and the open questions and decisions of spec.md.

```sh
plastic intent spec ID
```

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ID` | the intent | |

## The events of one call, step by step

![The events of one call of plastic intent spec](events.svg)

The boxes on the left run in order. The boxes on the right are the ways the call stops or ends at that step.

## What one call changes

This command changes nothing.

The command is `Plastic::Commands::Intent::Spec`, in [`commands/intent/spec.rb`](../../../../lib/plastic/commands/intent/spec.rb).
