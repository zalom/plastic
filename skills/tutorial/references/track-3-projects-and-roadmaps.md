# Track 3: Projects and roadmaps

## Who it is for and what you will have done

For someone ready to see a founding idea grow past a single intent: into a small real
project, a handful of related intents, and a roadmap that plans and tracks them as one
batch. After this track, a small project (a personal todo app, in the walkthrough below)
will exist with more than one intent inside it and a roadmap file describing the batch.

## Before you start

Run `/plastic-update` first (`$plastic-update` on Codex), so the commands below match what is
actually installed.

Work in a sandbox: this whole track is a walked example. It creates a real project directory
and a real roadmap file on disk, but the project is a throwaway one made for learning, not
one this tutorial keeps or ships.

## Stations

### 1. Start from a founding implementation intent

Create and board an intent the same way as track 1, stations 1 and 2: `/plastic-intent-creating`,
then `/plastic-intent-continuing`. Describe something meant to grow into a small real project,
for example "build a personal todo app."

Then type `/plastic-intent-speccing` and record a couple of real rulings on this founding
intent, for example the language or how tasks get stored. Keep it short: this intent only
needs enough decisions for the new project to inherit, not a full design.

Checkpoint: explain why this intent is "founding": its decisions are about to carry forward
into a whole new project.

### 2. Grow it into a project

Type `/plastic-project-creating`.

Artifact: a new project directory, an `AGENTS.md` file carrying the founding intent's
decisions, the project's own intent store, and a new entry in `projects.yml` registering it.

Checkpoint: open `AGENTS.md` and find at least one line that traces back to a decision
recorded in the founding intent back in station 1.

### 3. Add more intents inside the project

Type `/plastic-intent-creating` at least twice, from inside the project, describing two
pieces of real work, for example "add a task list model" and "add a due date field."

Artifact: two or more intent directories inside the project's own store, separate from the
global store the founding intent came from.

Checkpoint: point at the project's store path and confirm both new intents live there, not
in the global store.

### 4. Plan a delivery batch

Type `/plastic-roadmap`.

Teach the roadmap file shape exactly: a title and short meta header, a `## Goal` section in
prose describing what "done" looks like for the whole batch, a `## Batches` section (an
ordered list of groups of intents; intents inside one batch are safe to run in parallel,
batches themselves run one after another), and an append-only, dated `## Log`. `INDEX.md`
stays the single source of truth for each intent's status; the roadmap only mirrors it.

Artifact: a new `roadmaps/<slug>.md` file, sitting next to the project's `INDEX.md`, listing
the two or more intents from station 3 across one or more batches.

Checkpoint: name which of the two intents from station 3 share a batch (so they run in
parallel) and which one, if any, sits in a later batch (so it waits).

### 5. Drive delivery with /goal

`/goal` is a Claude Code harness command, not a Plastic skill. It sets a completion condition
and Claude keeps working, turn after turn, until a fast checker model confirms from what
Claude has actually reported that the condition holds; `/goal` never reads files on its own,
so the condition has to name a check Claude's own output can prove.

Turn the roadmap's `## Goal` and current `## Batches` into that condition, for example:

`/goal every intent in batch 1 of roadmaps/<slug>.md shows Completed in INDEX.md, and the test
suite is green`

Claude then works through the batch itself, one intent at a time, and stops on its own once the
checker agrees the condition holds. Run `/goal` with no argument at any point to see how long
it has run and how many turns it has spent; run `/goal clear` to stop it before that.

On a harness without `/goal`, just tell the agent to deliver the roadmap in auto mode instead.

Checkpoint: point at the exact file (`roadmaps/<slug>.md`) whose `## Goal` and `## Batches`
sections you turned into the condition above.

### 6. Merge discipline and releases

No command run here; describe the step instead. Each delivered intent's code merges to main
as it lands. When the batch (or a meaningful slice of it) is ready to ship, cutting a release
runs through `/plastic-releasing`, which merges, bumps the version, tags, and completes the
intents it collects.

Releases and any npm publish step are described here, not run: this walkthrough stays in a
sandbox and never touches a real package registry.

Checkpoint: explain why a release completes the intents it collects, rather than an intent
waiting on a release to exist first.

## Wrap and where to go next

This is the same What, Why, How, Exec cycle from tracks 1 and 2, repeated across a project
and gathered by a roadmap. Read
[`using-plastic-with-claude-code.md`](https://github.com/zalom/plastic/blob/main/docs/guides/using-plastic-with-claude-code.md) for roadmap-driven delivery in more depth,
including a real worked roadmap. For the exact roadmap file format beyond what this
walkthrough covers, the `plastic-roadmap` skill itself is the reference.
