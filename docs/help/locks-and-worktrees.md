# Locks and Worktrees

This chapter holds the delivery lock, the code worktree and the station-by-station delivery
table. Nothing here blocks a write: the lock and the worktree are how an
auto team keeps one delivery in one place, not fences.

## The delivery lock

The delivery lock names the session delivering an intent in auto mode. Locks and worktrees
exist only for auto teams: an interactive session working direct or thinking takes no lock.

For an auto team, exactly one session develops an intent's delivery at a time. The lock is one
row of the `locks` table in the machine's `local.db`, keyed by the store and the intent. The row
holds the session id, the mode, and the times the lock was taken and last renewed. The session
id is the only authorization identity. Liveness is a lease: the record hook (`plastic hook record`)
renews every lock row the session holds, and a lock counts as expired when its renewal is older than the TTL of 1800
seconds.

`plastic auto ID` takes the lock. Another session that finds a live lock gets exit 3 and backs
off. An expired lock is taken over by the next `plastic auto ID`. Ending the intent with
`plastic intent end` releases the lock. To read a lock back, run `plastic intent lock status ID`.
It prints the session, the mode, the taken and renewed times, whether the lock is live or
expired, and the code worktree when the store's project names a repository.

The record hook resolves the current session in a fixed precedence: the stdin `session_id`
first, then the `CLAUDE_CODE_SESSION_ID` environment variable, then a derived key when neither
is present. See [`docs/internals.md`](https://github.com/zalom/plastic/blob/main/docs/internals.md) for depth.

There is exactly one lock in Plastic. A second lock for maintenance would mislead: a resuming
session could mistake a lock held by a maintenance session for an active delivery. Maintenance detects a live delivery lock and defers; it never
takes a lock of its own.

## The code worktree

In auto mode the worktree is the lock: the intent's code worktree is where its one delivery
happens. Every code-touching auto intent gets its own git worktree named `{id}--{slug}`, and all
code edits for that intent happen inside it. Plastic runs no version control command, so it
never creates the worktree. `plastic auto ID` resolves the project repository from
`projects.yml`, computes the path and branch, and prints them:

```text
worktree: /home/you/greeter/.claude/worktrees/2--shout
branch: plastic/2--shout
next: git -C /home/you/greeter worktree add /home/you/greeter/.claude/worktrees/2--shout -b plastic/2--shout
```

While the folder does not exist, that `git -C <repo> worktree add <path> -b <branch>` command is
the `next:` line, and the agent runs it. Once the folder exists, the `next:` line is
`plastic intent brief ID`. There is one worktree per project intent, the code worktree at
`<repo>/.claude/worktrees/{id}--{slug}` on branch `plastic/{id}--{slug}`.

Plastic does not provision a second worktree for lifecycle-doc writes. The harness's own native
worktree covers that need: Claude Code manages its own worktrees at
`<repo>/.claude/worktrees/{name}`, and Codex manages its own at `$CODEX_HOME/worktrees` (default
`~/.codex/worktrees`).

A store-only intent that touches no project code (a research or decision intent in the global
store, or a store whose project names no repository) gets the lock only: no repository
resolves, so `plastic auto ID` prints no worktree and the next step is the brief. This is not a
failure, only nothing to report.

Cleanup is the closer's own step: Plastic neither checks that the code is merged nor removes the
worktree. After committing and merging, run `git worktree remove` on the code
worktree, so no worktree is ever left orphaned, and clear a stale worktree reference with
`git worktree prune`.

### Intent delivery, station by station

How one auto-team intent travels from boarding to the end, and what the lock does at each
station. Nothing in the third column blocks; the fourth column is what gets written down.

| Station | Delivered artifact | Lock steps | Record |
|---|---|---|---|
| What (create) | the intent's rows and its folder | no lock yet | the intent row |
| Why | `spec.md` | no lock yet; `plastic intent spec ID` names the open decisions | the spec and the rulings as rows |
| Start (board) | none (a procedure, not a stage) | `plastic auto ID` takes the lock row and sets the intent active, then prints the code worktree and its git command | the lock row in `local.db` |
| How | the work graph of the intent | the record hook renews the lock | node and edge rows |
| Exec | code on the intent branch | renewal continues; code edits stay in the code worktree | node results |
| End (done) | `outcome.md` | `plastic intent end ID` closes the intent and releases the lock; the session that delivered it closes it after the code is merged, with no lock handover | the intent closed as done |
| Maintenance | revisions | detects a live lock and defers; never takes one | the revision rows |
