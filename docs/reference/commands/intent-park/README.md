# plastic intent park

Park an intent in progress with the reason it waits; intent start resumes it.

```sh
plastic intent park ID REASON...
```

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ID` | the intent | |
| `REASON` | why the work waits | |

## The events of one call, step by step

![The events of one call of plastic intent park](events.svg)

The boxes on the left run in order. The boxes on the right are the ways the call stops or ends at that step.

## What one call changes

| What changes | Where | Reach |
| --- | --- | --- |
| The intent is parked with its reason | the work graph database, in the store folder | goes with the store |
| The files of the intent and the index of the store are rewritten | the store folder | goes with the store |

Goes with the store: the files of the store carry the change, and `plastic sync up` rebuilds it on another machine. The database files themselves stay on this machine.

The command is `Plastic::Commands::Intent::Park`, in [`commands/intent/park.rb`](../../../../lib/plastic/commands/intent/park.rb).
