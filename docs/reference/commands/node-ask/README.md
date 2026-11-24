# plastic node ask

Move a claimed node to needs_info with a question for the owner.

```sh
plastic node ask ID NODE TEXT [--file PATH]
```

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ID` | the intent | |
| `NODE` | the node | |
| `TEXT` | the question and what was tried | |
| `--file PATH` | a document of the intent folder that the sync reads in as the result; repeat for more; every changed file when left out | `[]` |

## The events of one call, step by step

![The events of one call of plastic node ask](events.svg)

The boxes on the left run in order. The boxes on the right are the ways the call stops or ends at that step.

## What one call changes

| What changes | Where | Reach |
| --- | --- | --- |
| The node waits for the owner's answer to the question | the work graph database, in the store folder | goes with the store |
| The files of the intent and the index of the store are rewritten | the store folder | goes with the store |

Goes with the store: the files of the store carry the change, and `plastic store sync up` rebuilds it on another machine. The database files themselves stay on this machine.

The command is `Plastic::Commands::Node::Ask`, in [`commands/node/ask.rb`](../../../../lib/plastic/commands/node/ask.rb).
