# plastic config set

Write one setting to the settings rows, globally or for one harness.

```sh
plastic config set KEY VALUE [--harness NAME]
```

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `KEY` | the setting, as its dotted name | |
| `VALUE` | the new value | |
| `--harness NAME` | the harness whose settings to use; the global settings when left out |  |

## The events of one call, step by step

![The events of one call of plastic config set](events.svg)

The boxes on the left run in order. The boxes on the right are the ways the call stops or ends at that step.

## What one call changes

| What changes | Where | Reach |
| --- | --- | --- |
| The setting is written to the settings rows in plastic.db, and config.yml is printed from them | the Plastic home folder | stays on this machine |

The command is `Plastic::Commands::Config::Set`, in [`commands/config/set.rb`](../../../../lib/plastic/commands/config/set.rb).
