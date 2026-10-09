# Plastic

Plastic is one command, `plastic`. `plastic help` lists commands, `plastic help <command>`
gives one command's options, and `plastic help tools` covers RTK, QMD and Enola.

`plastic status` shows active work in every store. `plastic graph resume` says where
the work stopped and what runs next, across several projects with `--stores a,b`. When a
person says "continue", run it. `plastic next` prints that one action.

A command ends with a `next:` line naming what to run now, and a `because:` line
giving the rule that chose it. Run it unless asked for something else. A call with
nothing to run next prints no `next:` line and still prints `because:`.

`--json` gives any command's result as data, except the installer commands and `plastic hook`.

git is a hard dependency: Plastic needs it installed, and agents run it, never Plastic's code.

Pull request: What, Why, How, Tests (`plastic help completion-and-done`).

Agents run every command, from opening an intent to closing it, without asking. A person
is in the loop for decisions and the direction of the work only. Exit codes: 0 succeeded,
1 failed, 2 called wrongly, 3 refused. Exit code 3 is such a decision: report what was
refused, stop, and never retry with a different flag.
