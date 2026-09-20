# Configuration

## Options on every command

| Option | Effect |
| ------ | ------ |
| `--json` | Prints the result as data with stable keys. The installer commands do not take it. |
| `--help`, `-h` | Prints the usage line of the command. |
| `--project SLUG` | On `continue` and `next`, names a project other than the one in the current directory. |

## Files

| File | Holds |
| ---- | ----- |
| `~/.plastic/config.yml` | Global settings, such as the context thresholds. |
| `~/.plastic/projects.yml` | The registered projects: slug, path and governing intent. |
| `~/.plastic/PLASTIC.md` | The instruction text the agent carries. The installer replaces it on every update. |

The `plastic` command has no configuration file of its own in this batch.
