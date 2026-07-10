# Track 2: Auto, hand delivery to the agent

## Who it is for and what you will have done

For someone who has seen the stages once (track 1) and now wants to hand the work to the
agent, watch it move through the gates and reports on its own, and learn how to check in on
it and step back in later. After this track, one small intent will have been delivered by the
agent end to end, and pausing and resuming that delivery will feel familiar.

## Before you start

Run `/plastic-update` first, so the commands below match what is actually installed.

Work in a sandbox: a throwaway git repository, or a global-store intent. Nothing in this
track touches a real project.

## Stations

### 1. Board a small intent and choose auto

Start from an active intent (create one first with `/plastic-intent-creating` if none
exists, the same way as track 1 station 1). Type `/plastic-auto`.

Artifact: the delivery lock arms, and the agent announces it is taking over the intent for
autonomous delivery.

Checkpoint: name the one precondition auto needs before it will start: an active intent must
already exist for the intent you name. (Say "auto" with nothing named, and it can pick a
queued intent from the dashboard's queue itself.)

### 2. What auto does, and what stays with the user

No new command at this station. Watch how the work splits.

Auto owns How (the plan, the checklist, the action files) and Exec (the code, the tests, the
mechanical close) from here on. Inside Exec it follows a few fixed habits: it syncs its
working copy with the main line before touching anything, ticks each task the moment it
lands rather than batching several into one later edit, and independently verifies its own
work (running the test suite, or checking the changed file) before presenting anything back
to you. For a task shaped like an audit or a sweep, checking many files rather than building
one artifact, it also drops a short methods report into `resources/` before the gate, so you
can review how it checked, not just what it found.

The user keeps two things: the rulings made along the way, and the review points, moments
auto is built to pause for, such as confirming a project path or stopping before a
destructive action with no safe way back. When auto tells you to run a command yourself
("run /plastic-intent-speccing"), that is an instruction for you to type; it is a different
thing from the prompts auto hands to its own dispatched subagents, and the two are never
mixed up in what it tells you.

Checkpoint: name one thing auto will always stop and ask about, rather than decide alone.

### 3. Walking the gates

No new command. Auto still honors every hard gate a guided session would hit: the delivery
lock (one owner at a time), the code gate (shut until `plan.md` and `checklist.md` exist),
and the create gate (intents only come from the tool that makes them, never hand-authored).
One gate, retrieval, is advisory only and never blocks anything; it just adds a note.

Checkpoint: read one gate message from the run so far and say whether it is one of the hard
gates or the one advisory note.

### 4. Reading the per-stage reports

No new command. At each stage boundary (What, Why, How, Exec, Done) the agent briefs in a
fixed three-line shape: State (what happened and why it matters), Risk (the one thing that
could bite, or "nothing flagged"), and Call (the decision left to the user, or the call the
agent is taking on its own).

Checkpoint: in the most recent report, point at the State line, the Risk line, and the Call
line.

### 5. Continue and where-was-I after time away

Type `/plastic-continuing`.

Artifact: the current state, presented and then the session stops. If a specific intent is
named, the agent reads its stage and savepoint and resumes exactly there, rather than
starting over.

Checkpoint: after stepping away and running this command, name the stage the intent resumed
at and how that matched what was actually on disk.

## Wrap and where to go next

Auto keeps the same stages and the same gates as guided; the only difference is who steers.
Read `docs/guides/pick-your-mode.md` for the honest trade-off between guided and auto, and
`docs/guides/using-plastic-with-claude-code.md` for how that choice feels day to day and how
it connects to roadmap-driven delivery. For denial messages met along the way, read
`docs/guides/what-the-gates-are-telling-you.md`.

Note on terms: "guided" means the user starts each stage with a command and the agent
narrows the thinking inside it, the same shape track 1 walked. "Manual", editing project
files outside the lifecycle entirely, is not a third mode; it is the anti-pattern both guided
and auto exist to avoid.
