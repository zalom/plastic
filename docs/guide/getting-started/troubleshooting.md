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
`next: plastic help`.

**Ruby is too old.** See "A clean Mac" in [INSTALL.md](../../../INSTALL.md).

## Repair a broken install

Skills are missing, hooks do not fire, or an old plugin layout is left over. Run the installer
again:

```bash
plastic install --reinstall --claude
```

The installer is safe to repeat. It removes files that Plastic no longer ships and any old
plugin layout.

## Check the installation

Run the `plastic-doctor` skill in your agent. A `plastic doctor` command is not part of this
batch.
