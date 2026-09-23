# Plastic

Plastic is one command, `plastic`. Run `plastic help` for the list of commands
and `plastic help <command>` for one command's options.

Open a session with `plastic status`, which shows the active work in every
store. Then run `plastic continue` for the project you are in: where it stands
and what runs next. `plastic next` prints that one action on its own.

Every command ends with two lines. The `next:` line names the command to run
now, and you run it unless the person asks for something else. The `because:`
line gives the rule that chose it.

Add `--json` to any command except the installer commands (`install`, `update`,
`uninstall`, `rollback`) and `plastic hook` to get the same result as data.

Exit codes: 0 succeeded, 1 failed, 2 called wrongly, 3 refused. Exit code 3
means the step belongs to the owner. Report what was refused and stop. Never
retry a refused command with a different flag.
