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

Hooks do not fire, agents are missing, or an old plugin layout is left over. Run the installer
again from the package:

```bash
npx -y @zalom/plastic install --reinstall --claude
```

In 2.0.2, the installed `plastic install --reinstall` stops with `same file` because it copies
`PLASTIC.md` onto itself. Run it through `npx`.

The installer is safe to repeat. It removes files that Plastic no longer ships and any old
plugin layout.

## Check the installation

Run `plastic doctor`. It checks the install and every store, and prints one line for each
finding. Add `--json` for the full report as data.
Each finding that is not a pass names its own repair.

The following table lists the three forms of the command:

| Command | What it checks |
| ------- | -------------- |
| `plastic doctor` | The install and every store. |
| `plastic doctor --core` | The install only. This check is fast. |
| `plastic doctor --store WHICH` | One store. `WHICH` is `global` or a project slug. |

The command exits with code 1 when the doctor reports a warning or a failure.

## Report a problem

The following command saves a report and prints a link that opens a GitHub issue with the
report filled in:

```bash
echo "What happened, and what you expected" | plastic feedback "A short title"
```

Nothing is sent until you open the link and submit the issue.
