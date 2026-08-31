# Reading the ledgers

Who this is for: someone who just worked with Plastic for a session, or watched an agent
work, and wants to know where that work was written down and how to read it.

After this guide you will be able to open the two ledgers Plastic keeps, read every line in
them, and tell at a glance what an intent or a day has reached.

Commands below use Claude Code's slash form. On Codex CLI, invoke the same skill with a dollar
prefix instead (for example `$plastic-doctor`), or let Codex select one implicitly by matching
its description.

## Two ledgers, not one

Plastic writes two kinds of ledger, and nothing else records work:

- **The intent ledger**, `savepoint.md` inside an intent's directory. One line per milestone
  of that one intent.
- **The day ledger**, one directory per calendar day under the global store,
  `~/.plastic/store/.sessions/<YYYYMMDD>/`. It records every session's requests for that day,
  whichever project they touched.

Both are append-only, written by hooks, and never blocked: Plastic records what you did, it
does not stop you from doing it.

## The intent ledger

Open `savepoint.md` in any intent directory. Every line has the same shape: a UTC timestamp,
a stage, and a milestone, separated by two spaces.

```
2026-06-16T14:02:00Z  What    ID--slug.md
2026-06-16T14:20:00Z  Why     spec.md created
2026-06-16T15:10:00Z  How     plan.md created
2026-06-16T15:11:00Z  How     checklist.md created
2026-06-16T15:45:00Z  Review  plan REVISE, folded
2026-06-16T16:20:00Z  Commit  abc1234 tests red
2026-06-16T16:35:00Z  Commit  def5678 2460 runs, 0 failures
2026-06-16T16:40:00Z  Exec    outcome.md created
2026-06-16T16:41:00Z  Done    delivered
```

- The first line is stamped when the intent is created. The last line, `Done delivered` or
  `Done abandoned`, is stamped when it is closed. Between them, one line lands each time a
  lifecycle file (`spec.md`, `plan.md`, `checklist.md`, `outcome.md`) is written.
- The stage names are What, Why, How, Exec, and Done. They describe the shape of the record,
  not checkpoints you had to pass.
- Two more kinds record delivery mechanics rather than a stage: `Review` (one line per
  plan-review or post-execution-review verdict) and `Commit` (one line per commit landing
  during Exec), written through `scripts/savepoint-note --kind Review|Commit --text "..."`
  (intent 317). They keep the same line shape as every other kind and feed the delay report
  (`report-screen delay`); readers that pick the current STAGE (the dashboard, the spawn
  preamble, `report-screen state`) skip over them and use the last lifecycle line instead.
- The last LIFECYCLE line (What/Why/How/Exec/Done) is the intent's current stage. That is
  what the dashboard and the spawn preamble read. The last line of ANY kind is still what the
  intent screen's `Savepoint` field shows, since that field answers "when did this ledger
  last move," not "what stage is this."
- The file is rebuildable from the files on disk. If it looks wrong, run `/plastic-doctor` and
  ask it to rebuild the savepoint rather than editing the file by hand.

## The day ledger

Each day's directory holds three files:

- `<YYYYMMDD>.md`, the day's intent file. Its id is the date, digits only (`20260828`).
- `checklist.md`, one line per request that changed something on disk or produced an
  artifact. A question you asked and got answered is not recorded.
- `savepoint.md`, one line per event on those items.

A checklist line reads:

```
- [x] [a1b2c3d4] [plastic] rewrite the harness-adapters reference
```

The first bracket is the state, the second is the short session id that made the request,
the third is the project the working directory belonged to, and the rest is the request.

| Marker | State | Meaning |
|---|---|---|
| `~` | pending | the prompt arrived and nothing has landed yet |
| ` ` (space) | open | a file changed; the item is in progress |
| `x` | done | verified and committed |
| `>` | moved | carried to the next day's ledger |
| `-` | dropped | abandoned on purpose |
| `^` | promoted | became a registered intent of its own |

A day `savepoint.md` line reads `2026-08-28T14:02:00Z  Item  [session] [project] summary`,
with the event one of `Item` (a request was recorded), `Done` (an item was ticked), or `Note`.
Sessions share one day's files safely: every append takes a file lock, so two sessions never
interleave a line.

## The pointer and the heartbeat

Each live session keeps two small files under `~/.plastic/store/.tmp/<session>/`, where
`<session>` is the first eight characters of the session id:

- `current`, the pointer. It holds one line: today's day id (the day ledger takes the record)
  or an intent id (an auto team owns the record). Session start writes today's day id into it.
- `heartbeat`, a timestamp the hooks refresh. It is how a later session tells whether this one
  is still alive.

Nothing in `.tmp/` is durable or committed (it carries its own `.gitignore`). Losing it costs
nothing; the next session start recreates it.

## The hand-off and the day summary

Two renderings sit on top of the day ledger. Neither is a ledger of its own: both are
rebuilt in full from `checklist.md` and `savepoint.md` every time they are written, so a
lost or stale copy costs nothing.

- **The hand-off**, `handoff--<session>.md` in the day directory, one file per session. It is
  written at every ticked item, at the moment before a compaction, and at session close. It
  lists that session's open and done items, its last ten events, a one-line count for each
  other session that day, and how to resume. After a compaction or a new session, read the
  newest one for the day; it is the prior session's own account of where things stand.
- **The day summary**, the block the session-start hook injects right after the
  `day ledger <day> joined` line. It carries the open items across every session, the last
  five done, the live auto intents (an Active intent holding a fresh `delivery.lock`, with its
  latest savepoint line), and the other sessions alive by their heartbeat. It never carries
  the raw ledger, only this summary, and it stays under three kilobytes. To see it outside a
  boot, run `ruby ~/.plastic/scripts/day-summary`.

## When you see a lock

`delivery.lock` appears in an intent directory only when an auto team is delivering that
intent. It names the owning session and stays fresh while that session's hooks touch it. An
interactive session working on its own never takes one. To inspect a lock, run
`/plastic-doctor check the lock status`; to take over one whose owner has gone quiet, ask
`/plastic-doctor` to reclaim it, which is recorded in the intent's `savepoint.md`.

## What to read next

Once you can read the ledgers, read
[reading-a-delivered-intent.md](reading-a-delivered-intent.md) to learn how to check what an
intent actually shipped once it is done.
