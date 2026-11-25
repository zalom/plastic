# Plastic

Plastic is one command, `plastic`. `plastic help` lists commands, `plastic help <command>`
gives one command's options, and `plastic help tools` covers RTK and Enola.

`plastic status` shows the work of every store by group. `plastic graph resume` says where
the work stopped and what runs next, across several projects with `--stores a,b`. When a
person says "continue", run it. `plastic next` prints that one action.

Before re-deriving a decision, run `plastic search TERMS`. `plastic intent rule ID TEXT` records
one as `D1: text`, `--adds D1` writes `D1.1`, and `--rewrites D1` replaces it and drops its
additions. `--supersedes` is gone.

When a person says "Load project X" or "Load projects X, Y, Z", run `plastic project load`
with them, do what its `then:` line says, and run it again to refresh. The next work
waits for the person's ask.

A command ends with a `next:` line naming what to run now, and a `because:` line
giving the rule that chose it. Run it unless asked. With nothing to run,
a call prints only `because:`.

`--json` gives any command's result as data, except the installer commands and `plastic hook`.

git is a hard dependency: agents run it, never Plastic's code.

Pull request: What, Why, How, Tests (`plastic help completion-and-done`).

Commands write an intent's core files, and only `resources/` is open to agents. Record the
delivery with `plastic intent note ID TEXT --kind Merged`, `Committed` or `Delivered`.
Record a report with `plastic intent report ID PATH`. Research, a comparison of options, a review
or audit that is the work, and a proposal for a ruling get a report with no ask. A plan, a delivery
report or an explainer gets one only when asked or named by `reports.mandatory`. Tell by the
request's words ("report", "artifact", "html" ask; "research", "compare", "audit", "verify" name
the work), the intent's kind or title, and whether the result is a finding or code.

<!-- layout:start -->
Intent folder `store/{id}--{slug}/`: `intent.md`, `spec.md`, `outcome.md`, printed `graph.json`, `work.log`, `context.json`, and `resources/` (`output/reports`, `output/files`, `references`, `tmp`).
Sync up names any other file: `plastic help intent-folder`.
<!-- layout:end -->

In guided work the owner's word to deliver is the go-ahead, and the agent records it with
`plastic intent approve`. `plastic intent auto ID` hands the What, Why and How to agents, who
run `plastic intent approve ID` themselves when the `because:` line of `plastic intent spec` names it.
`plastic intent start ID` starts guided work. `plastic intent park ID REASON` parks started
work with the reason it waits. When the owner says auto, background agents deliver from the
first step, and the main session orchestrates: it dispatches, records and reports, never
blocks, and runs `plastic graph lapsed` on a timer to restart the helper it names.

Agents run every command without asking. A person
is in the loop for decisions and the direction of the work only. Exit codes: 0 succeeded,
1 failed, 2 called wrongly, 3 refused. Exit code 3 is such a decision: report what was
refused, stop, and never retry with a different flag.
