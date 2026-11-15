# plastic roadmap edge remove

Remove one needs edge from a roadmap.

```sh
plastic roadmap edge remove SLUG FROM TO [--dry-run]
```

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `SLUG` | the roadmap | |
| `FROM` | the edge's start | |
| `TO` | the edge's end | |
| `--dry-run` | preview the call in a disposable copy | `false` |

## The events of one call, step by step

![The events of one call of plastic roadmap edge remove](events.svg)

The boxes on the left run in order. The boxes on the right are the ways the call stops or ends at that step.

## What one call changes

| What changes | Where | Reach |
| --- | --- | --- |
| The edge between two items of the roadmap is removed | the work graph database, in the store folder | goes with the store |
| The files of the roadmap are rewritten | the store folder | goes with the store |

Goes with the store: the files of the store carry the change, and `plastic sync up` rebuilds it on another machine. The database files themselves stay on this machine.

The command is `Plastic::Commands::Roadmap::Edge::Remove`, in [`commands/roadmap/edge/remove.rb`](../../../../lib/plastic/commands/roadmap/edge/remove.rb).
