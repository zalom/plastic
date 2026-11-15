# plastic roadmap open

Open a ready item's intent, with its spec held in rows.

```sh
plastic roadmap open SLUG ITEM
```

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `SLUG` | the roadmap | |
| `ITEM` | the item to open | |

## The events of one call, step by step

![The events of one call of plastic roadmap open](events.svg)

The boxes on the left run in order. The boxes on the right are the ways the call stops or ends at that step.

## What one call changes

| What changes | Where | Reach |
| --- | --- | --- |
| The item's intent is opened and the item points to it | the work graph database, in the store folder | goes with the store |
| The files of the intent and the index of the store are rewritten | the store folder | goes with the store |
| The files of the roadmap are rewritten | the store folder | goes with the store |

Goes with the store: the files of the store carry the change, and `plastic sync up` rebuilds it on another machine. The database files themselves stay on this machine.

The command is `Plastic::Commands::Roadmap::Open`, in [`commands/roadmap/open.rb`](../../../../lib/plastic/commands/roadmap/open.rb).
