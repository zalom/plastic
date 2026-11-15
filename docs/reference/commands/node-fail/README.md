# plastic node fail

Mark a claimed node failed, with the reason as TEXT.

```sh
plastic node fail ID NODE TEXT
```

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ID` | the intent | |
| `NODE` | the node | |
| `TEXT` | why it failed | |

## The events of one call, step by step

![The events of one call of plastic node fail](events.svg)

The boxes on the left run in order. The boxes on the right are the ways the call stops or ends at that step.

## What one call changes

| What changes | Where | Reach |
| --- | --- | --- |
| The node is marked failed with the reason | the work graph database, in the store folder | goes with the store |
| The files of the intent and the index of the store are rewritten | the store folder | goes with the store |

Goes with the store: the files of the store carry the change, and `plastic sync up` rebuilds it on another machine. The database files themselves stay on this machine.

The command is `Plastic::Commands::Node::Fail`, in [`commands/node/fail.rb`](../../../../lib/plastic/commands/node/fail.rb).
