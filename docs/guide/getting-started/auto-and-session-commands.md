# Auto and session commands

The auto commands serve a team of agents that delivers one intent. The session commands keep
the day ledger, which is the record of what each session did. Both groups replace skills that
an agent used to read as prose.

## Auto commands

The following table shows each command an auto team runs and what it does:

| Command | What it does |
| ------- | ------------ |
| `plastic auto ID` | Takes the delivery lock of intent `ID` for this session, sets the intent active, and prints the code worktree and its branch. The agent makes the worktree at the printed path on the printed branch. Given a roadmap slug instead, it arms the roadmap's first item in flight, or names `plastic roadmap open SLUG ITEM` for the first ready item. |
| `plastic intent lock status ID` | Prints the session that holds the lock, its mode, when it was taken and renewed, whether it is live or expired, and the code worktree. |
| `plastic intent brief ID` | Prints the text that a spawned agent starts from. |

`plastic auto` takes exactly one id. An unknown roadmap exits 1. A live lock that belongs to
another session exits 3, and so do an open decision and a missing done criterion. Run
`plastic intent lock status ID` to see who holds the lock. An expired lock is taken over by
the next `plastic auto ID`, and `plastic intent end` releases the lock.

## Session commands

The following table shows each session command and what it does:

| Command | What it does |
| ------- | ------------ |
| `plastic session summary` | Prints the day ledger's open items and recent activity. |
| `plastic session handoff` | Writes this session's hand-off into the day ledger. |
| `plastic session commit "SUMMARY"` | Commits one verified checklist item with `SUMMARY` as the message. |

Every command takes `--json`. `plastic session commit` with no summary exits 2.

## Where the longer text lives

The rules for the auto team are help chapters. The following table shows where to read each
one:

| Topic | Command |
| ----- | ------- |
| The auto track, step by step | `plastic help track-2-auto` |
| What an agent's report must hold | `plastic help agent-report-contract` |
| How the team is built | `plastic help agent-architecture` |
| Locks and worktrees | `plastic help locks-and-worktrees` |
