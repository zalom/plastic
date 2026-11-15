# plastic intent spec

Print the grilling method, how done criteria are written, and the open questions and decisions of spec.md.

Prints the grilling method, then one intent's open decisions.

```sh
plastic intent spec ID
```

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ID` | the intent | |

## The workflows of one call

![The workflows of one call of plastic intent spec](workflows.svg)

Each box is a workflow. The words between the boxes say when the call moves on, and the last boxes say how the call ends.

## The events of one call, step by step

![The events of one call of plastic intent spec](events.svg)

The boxes on the left run in order. The boxes on the right are the ways the call stops or ends at that step.

## What one call changes

This command changes nothing.

## What the agent workflow steps print

| Step | The text the agent gets |
| --- | --- |
| 5 | \<handoff text> |

The command is `Plastic::Commands::Intent::Spec`, in [`spec.rb:9`](../../../../lib/plastic/commands/intent/spec.rb#L9).
