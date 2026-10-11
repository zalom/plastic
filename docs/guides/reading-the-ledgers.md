# Reading the ledgers

Who this is for: someone who just worked with Plastic for a session, or watched an agent
work, and wants to know where that work was written down and how to read it.

After this guide you will be able to read the two records Plastic keeps, and tell at a glance
what an intent has reached and what the last session left.

Commands below are `plastic` commands. They run the same way in every agent and in a plain
shell.

## Two records

Plastic keeps two records of work:

| Record | Where | What it holds |
| ------ | ----- | ------------- |
| The savepoint lines | The `savepoints` table of the store's `work_graph.db`, printed to `savepoint.md` in the intent folder | One line for each step of one intent. |
| The sessions | The `sessions` table of the machine's `local.db` | One row for each harness session: its harness, its store, its first and last turn, how it ended, and its note. |

The hooks write the session rows. They never block: Plastic records what you did, and it does
not stop you from doing it.

## The savepoint lines

Open `savepoint.md` in an intent folder, `~/.plastic/stores/SLUG/store/ID--slug/`. A line has a
time with its UTC offset, two spaces, and what happened:

```
2026-06-16T14:02:00+00:00  Opened: Add a dark theme to the settings page
```

- `plastic intent new` writes the first line, `Opened:` and the title.
- A line written by hand reaches the rows through `plastic sync up`, like any other edit of a
  printed file.
- `plastic intent show ID` prints the last three lines as `savepoint:` rows, and the session
  start hook prints the last lines of the intent in progress.

The file is printed from the rows. If it looks wrong, run `plastic sync down` to print it again
rather than editing the rows by hand.

## The sessions

The session start hook, `plastic hook start`, writes a row for each new session. It names the
harness and records the store of the directory the session runs in. The stop hook,
`plastic hook stop`, stamps the last turn at the end of every turn. The end hook,
`plastic hook end`, sets the end time and the reason.

A session writes its one prose line with `plastic session note TEXT...`. The next session start
prints the previous session and its note, so a new session or a session after a compaction
starts from where the last one stopped.

## When you see a lock

A lock is a row in the `locks` table of `local.db`, taken when `plastic auto ID` arms an intent.
The row names the owning session. It stays live while the session's stop hook renews it, or
while the session holds a claimed node of the intent. Run `plastic intent lock status ID` to
inspect a lock. A live lock of another session is refused with exit 3, and an expired one is
taken over by the next `plastic auto ID`. [The node lifecycle](../concepts/node-lifecycle.md)
shows how a claim keeps the lock live.

## What to read next

Once you can read the records, read
[reading-a-delivered-intent.md](reading-a-delivered-intent.md) to learn how to check what an
intent actually shipped once it is done.
