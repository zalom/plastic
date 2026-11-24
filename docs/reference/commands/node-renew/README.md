# plastic node renew

Renew this session's claim on a node so it does not lapse.

```sh
plastic node renew ID NODE
```

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ID` | the intent | |
| `NODE` | the node | |

## The events of one call, step by step

![The events of one call of plastic node renew](events.svg)

The boxes on the left run in order. The boxes on the right are the ways the call stops or ends at that step.

## What one call changes

| What changes | Where | Reach |
| --- | --- | --- |
| The claim of this agent of the session on the node is renewed to now | the work graph database, in the store folder | stays on this machine |

The command is `Plastic::Commands::Node::Renew`, in [`commands/node/renew.rb`](../../../../lib/plastic/commands/node/renew.rb).
