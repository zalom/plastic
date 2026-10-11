# Configuration

## Options on every command

| Option | Effect |
| ------ | ------ |
| `--json` | Prints the result as data with stable keys. The installer commands and `plastic hook` do not take it. |
| `--help`, `-h` | Prints the usage line of the command. |
| `--project SLUG` | On a command that works on one project, names a project other than the one in the current directory. The installer commands and `plastic hook` do not take it. |

## Choices at install time

`plastic init` asks which agent harnesses to install into, and writes the defaults. A Claude Code
install writes the Plastic status line when the settings hold none. When they hold your own,
the installer asks in a terminal whether to switch, and keeps yours otherwise. The keys below
change the defaults.

## Keys in `config.yml`

`~/.plastic/config.yml` holds only the settings you changed. It has two sections:

```yaml
version: 3
global:
  runner:
    stop_hook: true
harnesses:
  codex:
    agents:
      models:
        plastic-executor: gpt-5.5
```

Plastic reads a setting in three layers. A later layer wins:

| Layer | Holds |
| ----- | ----- |
| The shipped defaults | Every key below, at its default. |
| `global` | Your settings for every harness. |
| `harnesses.NAME` | Your settings for one harness, such as `claude-code` or `codex`. |

Every hook reads the file again, so a change takes effect on the next hook.

| Key | Default | Meaning |
| --- | ------- | ------- |
| `statusline` | `true` | Lets the installer write the Plastic status line into Claude Code's settings. |
| `screens` | `true` | Registers the hook that shows Plastic's screens. |
| `runner.stop_hook` | `false` | Lets the stop hook keep a session working while its work graph has a node ready. |
| `review.pull_request` | `required` | `required` asks for a pull request before an intent ends. `off` skips it. |
| `migrate.remove_after_import` | `false` | Removes the old intent files after an import. |
| `advisor.enabled` | `true` | Installs the advisor agents. |
| `agents.models.AGENT` | the shipped model | The model of one agent, in a harness section. |
| `agents.efforts.AGENT` | the shipped effort | The effort of one agent, in a harness section. |
| `advisor.default` | `plastic-primary-advisor` | The advisor the advisor skill calls, in a harness section. |

Read and change the keys with `plastic config`:

| Command | Does |
| ------- | ---- |
| `plastic config list` | Lists every key with its value. |
| `plastic config get KEY` | Prints one value. |
| `plastic config set KEY VALUE` | Writes one value into the `global` section. |
| `plastic config` | Shows the on/off keys on a choice screen. |

Add `--harness NAME` to read or write one harness section. A name the harness registry does not hold is refused, and the
command lists the registered ones. A file written in the older flat layout is moved into the two sections on the next
install or `config set`. The install also moves the model and effort of an agent that no longer ships to the agent that
replaced it, such as `plastic-enforcer` to `plastic-planner`, and names each move it makes. When the section already
names the new agent, its own value stays.

## Files

| File | Holds |
| ---- | ----- |
| `~/.plastic/config.yml` | Your settings: a `global` section and one section per harness. |
| `~/.plastic/projects.yml` | The registered projects: for each slug, the path, the registration date, the status and an optional parent. |
| `~/.plastic/PLASTIC.md` | The instruction text the agent carries. The installer replaces it on every update. |

The `plastic` command has no configuration file of its own.
