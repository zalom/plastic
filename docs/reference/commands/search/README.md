# plastic search

Search literal indexed passages across selected stores.

Searches literal indexed passages in the selected local stores.

```sh
plastic search TERMS... [--source-project SLUG] [--limit N]
```

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `TERMS` | literal search terms | |
| `--source-project SLUG` | a source store | `[]` |
| `--limit N` | maximum passages | `20` |

## The events of one call, step by step

![The events of one call of plastic search](events.svg)

The boxes on the left run in order. The boxes on the right are the ways the call stops or ends at that step.

## What one call changes

This command changes nothing.

The command is `Plastic::Commands::Search`, in [`search.rb:8`](../../../../lib/plastic/commands/search.rb#L8).
