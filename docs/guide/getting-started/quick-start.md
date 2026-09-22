# Quick start

Plastic is one command, `plastic`. Three commands open a session.

```bash
plastic status
plastic continue
plastic next
```

- `plastic status` shows the active work in every store.
- `plastic continue` shows where the project in the current directory stands and what runs
  next. Add `--project SLUG` to name another project.
- `plastic next` prints that one action on its own. Add `--why` to see the rule that chose it.

## Read a result

Every command ends with two lines:

```text
next: plastic status
because: the command line works, so read the work next
```

The `next:` line names the command to run now. The `because:` line gives the rule that chose
it. Add `--json` to any of these commands to get the same result as data.

## Find a command

```bash
plastic help
plastic help next
```

`plastic help` lists every command. `plastic help next` prints the usage of one command.
`plastic next --help` prints the same line.

## Start your first intent

Intents are still created through the agent in this batch. Follow
[your first intent in 10 minutes](../../guides/your-first-intent-in-10-minutes.md).
