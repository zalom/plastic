# plastic node done

Mark a claimed node done, with its findings as TEXT.

```sh
plastic node done ID NODE TEXT [--file PATH] [--output PATH]
```

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ID` | the intent | |
| `NODE` | the node | |
| `TEXT` | what the work showed | |
| `--file PATH` | a document of the intent folder that the sync reads in as the result; repeat for more; every changed file when left out | `[]` |
| `--output PATH` | a file of JSON to store as the output of the node, which the nodes that need it read; refused when it is not JSON; the path is read relative to the current directory |  |

## The events of one call, step by step

![The events of one call of plastic node done](events.svg)

The boxes on the left run in order. The boxes on the right are the ways the call stops or ends at that step.

## What one call changes

| What changes | Where | Reach |
| --- | --- | --- |
| The node is marked done with its findings | the work graph database, in the store folder | goes with the store |
| The files of the intent and the index of the store are rewritten | the store folder | goes with the store |

Goes with the store: the files of the store carry the change, and `plastic store sync up` rebuilds it on another machine. The database files themselves stay on this machine.

The command is `Plastic::Commands::Node::Done`, in [`commands/node/done.rb`](../../../../lib/plastic/commands/node/done.rb).
