# Quick start

Plastic is one command, `plastic`. Three commands open a session.

```bash
plastic status
plastic graph resume
plastic next
```

- `plastic status` shows the active work in every store.
- `plastic graph resume` shows where the work of the project in the current directory
  stopped and what runs next. Add `--stores a,b` to read several projects. When a person
  says "continue", this is the command to run.
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

Create an intent with `plastic intent new "LINE"`. `plastic help tutorial` walks one small
change from that first line to merged code and a delivered close.
