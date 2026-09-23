# Track 2: Auto, hand delivery to the agent

## Who it is for and what you will have done

For someone who has seen the stages once (track 1) and now wants to hand the work to the
agent, watch it move through the stages and reports on its own, and learn how to check in on
it and step back in later. After this track, one small intent will have been delivered by the
agent end to end, and pausing and resuming that delivery will feel familiar.

## Before you start

Run `plastic update` first, so the commands below match what is
actually installed.

Work in a sandbox: a throwaway git repository, or a global-store intent. Nothing in this
track touches a real project.

## Stations

### 1. Board a small intent and choose auto

Start from an active intent (create one first with `plastic intent new` if none
exists, the same way as track 1 station 1). Run `plastic auto take ID`.

Artifact: the delivery lock arms (`delivery.lock` in the intent directory) and the code
worktree is made at `<repo>/.claude/worktrees/ID--slug` on branch `plastic/ID--slug`. The
command prints both:

```text
intent    2--shout
lock      acquired by auto-9184f6c4fa, auto mode
worktree  /home/you/greeter/.claude/worktrees/2--shout
```

Run from inside a conversation session, `plastic auto take` refuses with exit 3: an intent is
not delivered inline. The owner may approve an inline take with `--allow-inline`. Otherwise
the harness spawns the team, and the team takes the intent. Exit 3 means stop and report; never
retry with another flag on your own.

`plastic auto brief ID` prints the preamble the spawned lead starts from, and
`plastic auto lock status ID` shows who holds the lock.

Checkpoint: name the one precondition auto needs before it will start: the intent you name
must already exist and be active, in a registered project.

### 2. What auto does, and what stays with the user

No new command at this station. Watch how the work splits.

Auto owns How (`graph.md`, `nodes/`) and Exec (the code, the tests, the
mechanical close) from here on. Inside Exec it follows a few fixed habits: it syncs its
working copy with the main line before touching anything, ticks each task the moment it
lands rather than batching several into one later edit, and independently verifies its own
work (running the test suite, or checking the changed file) before presenting anything back
to you. For a task shaped like an audit or a sweep, checking many files rather than building
one artifact, it also drops a short methods report into `resources/` before the close, so you
can review how it checked, not just what it found.

The user keeps two things: the rulings made along the way, and the review points, moments
auto is built to pause for, such as confirming a project path or stopping before a
destructive action with no safe way back. When auto tells you to run a command yourself
("run plastic intent spec"), that is an instruction for you to type; it is a different
thing from the prompts auto hands to its own dispatched subagents, and the two are never
mixed up in what it tells you.

Checkpoint: name one thing auto will always stop and ask about, rather than decide alone.

### 3. Walking the record

No new command. Auto keeps one delivery in one place and writes down every move: the delivery
lock (one owner at a time, a `delivery.lock` file in the intent directory), the worktree (code
edits land on the intent's own branch), the savepoint ledger (one line per lifecycle file the
team writes), and the day ledger (the request that started this run moves from pending to open
when the first project file lands). Nothing blocks the team; the record is how you follow it.

Checkpoint: open the intent's `savepoint.md` and name the stage its last line records.

### 4. Reading the per-stage reports

No new command. At each stage boundary (What, Why, How, Exec) the agent briefs in a
fixed three-line shape: State (what happened and why it matters), Risk (the one thing that
could bite, or "nothing flagged"), and Call (the decision left to the user, or the call the
agent is taking on its own). That is the depth for a medium or large intent. A small intent
gets one briefing, at How, merging in what the earlier stages would have said.

Checkpoint: in the most recent report, point at the State line, the Risk line, and the Call
line.

### 5. Continue and where-was-I after time away

Run `plastic continue`.

Artifact: where the project stands and a `next:` line naming what runs next. `plastic
continue` only reads: it takes no lock and changes no file. To resume one intent, run
`plastic intent show ID`; its Next row names the step it resumes at, read from the files on
disk.

Checkpoint: after stepping away and running this command, name the stage the intent resumed
at and how that matched what was actually on disk.

### 6. The close

The lead closes the intent with `plastic intent end ID --delivered --summary "TEXT"`. The
close checks that the code branch is merged and refuses with exit 1 when it is not; Plastic
does not merge. It also refuses to deliver an untouched scaffold. On success it writes
`outcome.md` from the record, moves the intent to `## Completed`, and releases the lock and
the worktree.

Checkpoint: open `outcome.md` and read its Summary.

## Wrap and where to go next

Auto keeps the same stages and the same record as thinking; the only difference is who steers.
Read [`pick-your-mode.md`](https://github.com/zalom/plastic/blob/main/docs/guides/pick-your-mode.md) for the honest trade-off between the three modes, and
[`using-plastic-with-claude-code.md`](https://github.com/zalom/plastic/blob/main/docs/guides/using-plastic-with-claude-code.md) for how that choice feels day to day and how
it connects to roadmap-driven delivery. For where the team wrote its work down, read
[`reading-the-ledgers.md`](https://github.com/zalom/plastic/blob/main/docs/guides/reading-the-ledgers.md).

Note on terms: "guided" means the user starts each stage with a command and the agent
narrows the thinking inside it, the same shape track 1 walked. "Manual", editing project
files outside the lifecycle entirely, is not a third mode; it is the anti-pattern both guided
and auto exist to avoid.
