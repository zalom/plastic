# Track 1: Guided, your first intent

## Who it is for and what you will have done

For a new user who wants to feel the whole cycle once, one stage at a time, approving each
step before the next one starts. After this track, one small, real change will be delivered
end to end: a piece of work moved through What, Why, How, and Exec, with a finished
`outcome.md` to show for it.

## Before you start

Run `/plastic-update` first, so the commands below match what is actually installed.

Work in a sandbox: this track always creates a global-store intent; the throwaway repo below
is never registered as a Plastic project. Pick a throwaway git repository if you have one
handy, since the worked example edits its README: station 6's deliverable is that file edit.
No repo handy? Station 6's deliverable becomes a short written note saved in the intent's own
directory instead (see station 6). Either way, nothing in this track touches a real project.

## Stations

### 1. Create the intent

Type `/plastic-intent-creating` and describe the work in plain words, for example "add a
short Usage section to this project's README."

Artifact: a new intent directory, `{id}--slug.md`, plus the sentinel placeholder lifecycle
files (`spec.md`, `plan.md`, `checklist.md`, `outcome.md`) and empty `actions/` and
`resources/` folders.

Checkpoint: open the new file. It already has a real id and a one-line description; nothing
was hand-typed into it directly. That is the point: intents are always scaffolded by the
tool, never written by hand.

### 2. Board the intent

Type `/plastic-intent-starting`.

Artifact: a delivery lock (a `delivery.lock` file in the intent directory) naming this
session as the one owner, and a line in `savepoint.md` recording the stage. The agent then
asks exactly one question: "auto or guided?"

Checkpoint: answer "guided." Explain in one sentence why the lock matters: it stops two
sessions from editing the same intent at the same time.

### 3. Why, rulings one at a time

Type `/plastic-intent-brainstorming` (or `/plastic-intent-grilling` for a harder,
interview-style pass over the same ground). It asks conversational prose questions, one at a
time, never a multiple-choice menu, and answers them one at a time in return.

Artifact: `## Context` and `### Decisions` in the intent file fill in as each answer lands, and
each ruling also lands as its own `## Insights` entry the moment it is made, never batched for
later. This station's product is the enriched Why; it hands off to `/plastic-intent-speccing`
next, it does not write `spec.md` itself.

Checkpoint: after two or three answers, look at the intent file. Every ruling given out loud
is already sitting in `### Decisions` and in `## Insights`, in writing.

### 4. Consolidate the spec

Type `/plastic-intent-speccing`.

Artifact: `spec.md`, stamped with a tier (`S`, for this small worked example) and its eight
sections filled from the rulings recorded in station 3.

Checkpoint: name the stamped tier and point at one sentence in `spec.md` that traces back to
an answer given in station 3.

### 5. Plan

Type `/plastic-intent-planning`.

Artifact: `plan.md`, `checklist.md`, and at least one real `actions/ACTION_N.md`. At the S
tier used here, the planner consolidates the whole delivery into a single
`actions/ACTION_1.md` (the ordered steps plus the exact changes); the L tier (many
independent tasks, dispatched in parallel) instead gets one `actions/ACTION_N.md` file per
task. `checklist.md` follows a fixed form: tasks start under `## In Progress`, move to
`## Completed` as they land, and a `## Session Log` table records what happened each session.
A task that depends on an owner decision landing first (a destructive step, a structural
ruling) gets an `[ORCHESTRATOR]` prefix and blocks every other item until that decision is
made; this worked example has none.

Checkpoint: open `checklist.md`. Every task in `plan.md` has a matching checkbox under
`## In Progress`; that checklist, not `plan.md` itself, is what gets ticked off and moved to
`## Completed` during Exec.

### 6. Exec, verify before the gate

Type `/plastic-intent-executing`.

Teach the order: first the agent syncs its working copy with the main line, so no edit lands
on a path a merged change upstream has already touched or removed. Then it makes the change,
runs whatever verifies it (a test suite, or a manual check for a docs change like this one),
and only then ticks the checklist box, moving the task from `## In Progress` to
`## Completed` and adding a `## Session Log` row, before moving to the next task. Verifying
always comes before checking a box, never after, and each task is ticked the moment it lands,
never batched for later.

Artifact: the actual change on disk (the new README Usage section, or, in the global-store
fallback, a short written note saved as the intent's deliverable) and a fully ticked
`checklist.md`.

Checkpoint: find the new Usage section in the README (or the written note) and confirm every
box in `checklist.md` is checked and moved to `## Completed`, with a `## Session Log` row for
this session, before moving to station 7.

### 7. Done

Type `/plastic-intent-ending`.

Artifact: a real `outcome.md` (Summary, Delivered, Verification, Follow-ups), the intent
moved from `## Active` to `## Completed` in `INDEX.md`, and a closing `Done` line in
`savepoint.md`.

Checkpoint: open `outcome.md` and read its Summary. It should describe, in a sentence or
two, exactly the README section (or note) just delivered.

## Wrap and where to go next

That is the full cycle once: create, board, decide, spec, plan, build, done. Read
`docs/guides/your-first-intent-in-10-minutes.md` for the same path condensed to a single
read, and `docs/guides/what-the-gates-are-telling-you.md` for what to do if a station denies
an action instead of completing it.
