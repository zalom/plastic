# Troubleshooting

## Exit codes

| Code | Meaning | What to do |
| ---- | ------- | ---------- |
| 0 | The command succeeded. | Run the `next:` line. |
| 1 | The command failed. | Read the message on standard error. |
| 2 | The command was called wrongly. | Read the usage line printed with the error. |
| 3 | The command refused the step. | The step belongs to the owner. Report it and stop. |

## Common messages

**An unknown command.** `plastic` prints the closest command name when one is close. Run
`plastic help` for the full list.

**An unknown project.** `--project SLUG` takes a slug from `~/.plastic/projects.yml`. The
command exits with code 2.

**`plastic status` shows no work.** No store has an active intent. The result ends with
`next: plastic next`.

**Ruby is too old.** See "A clean Mac" in [INSTALL.md](../../../INSTALL.md).

## Repair a broken install

Hooks do not fire, agents are missing, or an old plugin layout is left over. Run the installer
again:

```bash
plastic install --reinstall
```

`plastic doctor` names each broken part and prints the command that repairs it.

The installer is safe to repeat. It removes files that Plastic no longer ships and any old
plugin layout.

## Check the installation

Run `plastic doctor`. It checks the installation, the databases and the hooks of the harness
the session runs in, and prints one line for each check. Add `--json` for the full report as
data. Each check that does not pass names its own repair.

The following table lists the two forms of the command:

| Command | What it checks |
| ------- | -------------- |
| `plastic doctor` | The installation, every store and the harness the session runs in. |
| `plastic doctor --harness NAME` | The same, for the harness `NAME`, such as `claude-code` or `codex`. |

The command exits with code 1 when a check finds a problem, and with code 0 and
`next: plastic status` when every check passes.
