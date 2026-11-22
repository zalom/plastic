# Plastic

Plastic is one command, `plastic`. `plastic help` lists commands, `plastic help <command>`
gives one command's options, and `plastic help tools` covers RTK, QMD and Enola.

`plastic status` shows the work of every store by group. `plastic graph resume` says where
the work stopped and what runs next, across several projects with `--stores a,b`. When a
person says "continue", run it. `plastic next` prints that one action.

When a person says "Load project X" or "Load projects X, Y, Z", run `plastic project load`
with those projects, do what its `then:` line says, and run it again to refresh. The next work
waits for the person's ask.

A command ends with a `next:` line naming what to run now, and a `because:` line
giving the rule that chose it. Run it unless asked for something else. A call with
nothing to run next prints no `next:` line and still prints `because:`.

`--json` gives any command's result as data, except the installer commands and `plastic hook`.

git is a hard dependency: Plastic needs it installed, and agents run it, never Plastic's code.

Pull request: What, Why, How, Tests (`plastic help completion-and-done`).

Record the delivery under Verification in outcome.md: `Merged:` for a merged pull request,
`Committed:` for a direct commit, and `Delivered:` only for work that no version control holds.
Delivered files go in the intent folder, under `resources/output/reports` or `resources/output/files`.
Record a report with `plastic intent report ID PATH`. Research, a comparison of options, a review
or audit that is the work, and a proposal for a ruling get a report with no ask. A plan, a delivery
report or an explainer gets one only when asked or named by `reports.mandatory`. Tell by the
request's words ("report", "artifact", "html" ask; "research", "compare", "audit", "verify" name
the work), the intent's kind or title, and whether the result is a finding or code. Product files
go to `resources/output/files`. Tool output, packets, plans, notes, link lists and parts of a
research job go to `resources/tmp`, and copies of outside material go to `resources/references`.

In guided work the owner's word to deliver is the go-ahead, and the agent records it with
`plastic intent approve`. `plastic intent auto ID` hands the What, Why and How to agents, who
run `plastic intent approve ID` themselves when the `because:` line of `plastic intent spec` names it.
`plastic intent start ID` starts an intent for guided work, `plastic intent auto ID` for agent
delivery, and `plastic roadmap auto SLUG` starts a roadmap's next item. `plastic intent park ID
REASON` parks started work with the reason it waits.
When the owner says auto, background agents or processes run the delivery from the first step.
The main session stays open as the orchestrator: it dispatches, records and reports, and
never blocks on the work.

Agents run every command, from opening an intent to closing it, without asking. A person
is in the loop for decisions and the direction of the work only. Exit codes: 0 succeeded,
1 failed, 2 called wrongly, 3 refused. Exit code 3 is such a decision: report what was
refused, stop, and never retry with a different flag.
