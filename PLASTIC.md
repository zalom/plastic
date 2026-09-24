# Plastic

Plastic is one command, `plastic`. `plastic help` lists commands, `plastic help <command>`
gives one command's options, and `plastic help tools` covers RTK, QMD and Enola.

`plastic status` shows the active work in every store. `plastic continue` says where
your project stands and what runs next. `plastic next` prints just that one action.

Every command ends with a `next:` line naming what to run now, and a `because:` line
giving the rule that chose it. Run the next: command unless asked for something else.

`--json` works on every command except `install`, `update`, `uninstall`, `rollback`
and `plastic hook`, and gives the same result as data.

Pull request: What, Why, How, Tests (`plastic help completion-and-done`).

Exit codes: 0 succeeded, 1 failed, 2 called wrongly, 3 refused. Exit code 3 means the
step belongs to the owner. Report what was refused, stop, and never retry with a
different flag.
