# plastic doctor

Check the installation, the databases, the hooks of this harness and the folder layout of each store, rebuild a search index that is out of step, and name each repair.

```sh
plastic doctor [--harness NAME]
```

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `--harness NAME` | the harness to check, such as claude-code; the one the call runs in when left out |  |

## The events of one call, step by step

![The events of one call of plastic doctor](events.svg)

The boxes on the left run in order. The boxes on the right are the ways the call stops or ends at that step.

## What one call changes

| What changes | Where | Reach |
| --- | --- | --- |
| The search index is rebuilt from the documents when it is out of step with them | the search index, in the store folder | stays on this machine |

The command is `Plastic::Commands::Doctor`, in [`commands/doctor.rb`](../../../../lib/plastic/commands/doctor.rb).
