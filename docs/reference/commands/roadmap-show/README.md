# plastic roadmap show

Print a roadmap's batches and items.

```sh
plastic roadmap show SLUG [--batch N]
```

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `SLUG` | the roadmap | |
| `--batch N` | only this batch |  |

## The events of one call, step by step

![The events of one call of plastic roadmap show](events.svg)

The boxes on the left run in order. The boxes on the right are the ways the call stops or ends at that step.

## What one call changes

This command changes nothing.

The command is `Plastic::Commands::Roadmap::Show`, in [`commands/roadmap/show.rb`](../../../../lib/plastic/commands/roadmap/show.rb).
