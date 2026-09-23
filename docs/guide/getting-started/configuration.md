# Configuration

## Options on every command

| Option | Effect |
| ------ | ------ |
| `--json` | Prints the result as data with stable keys. The installer commands do not take it. |
| `--help`, `-h` | Prints the usage line of the command. |
| `--project SLUG` | On `continue` and `next`, names a project other than the one in the current directory. |

## Choices at install time

The installer asks no questions. It writes the defaults, and the following flags change them:

| Flag | Effect |
| ---- | ------ |
| `--advisor NAME` | Sets the default advisor agent: `primary` or `secondary`. |
| `--no-advisor` | Installs no advisor agent. |
| `--statusline VALUE` | `keep` keeps a status line you already have. `plastic` replaces it with the Plastic one. Without the flag, your line stays. |

## Keys in `config.yml`

The following table lists the keys you are most likely to set in `~/.plastic/config.yml`. A
new install writes every key except `project_roots`:

| Key | Default | Meaning |
| --- | ------- | ------- |
| `project_roots` | `~/.plastic/projects` and `~/.plastic/stores` | The parent folders searched for this session's delivery locks. Projects themselves are found through `projects.yml`. |
| `stale_threshold_days` | `3` | The age at which a future intent is shown for triage. |
| `context_offer_tokens` | `150000` | The context size at which the agent offers to compact. |
| `context_insist_tokens` | `250000` | The context size at which the agent insists on compacting. |
| `agent.type` | `claude-code` | The agent that runs Plastic. |
| `agent.parallel_mode` | `agent-teams` | `agent-teams` runs teammates in parallel. `linear` uses subagents only. |

Edit the file to change a key.

## Files

| File | Holds |
| ---- | ----- |
| `~/.plastic/config.yml` | Global settings, such as the context thresholds. |
| `~/.plastic/projects.yml` | The registered projects: for each slug, the path, the registration date, the status and an optional parent. |
| `~/.plastic/PLASTIC.md` | The instruction text the agent carries. The installer replaces it on every update. |

The `plastic` command has no configuration file of its own.
