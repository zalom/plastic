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
| The claim of this session on the node is renewed to now | the work graph database, in the store folder | goes with the store |
| The files of the intent and the index of the store are rewritten | the store folder | goes with the store |

Goes with the store: the files of the store carry the change, and `plastic sync up` rebuilds it on another machine. The database files themselves stay on this machine.

The command is `Plastic::Commands::Node::Renew`, in [`commands/node/renew.rb`](../../../../lib/plastic/commands/node/renew.rb).
