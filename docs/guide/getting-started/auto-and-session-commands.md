# Auto and session commands

The auto commands serve a team of agents that delivers one intent. The session commands keep
the day ledger, which is the record of what each session did. Both groups replace skills that
an agent used to read as prose.

## Auto commands

The following table shows each auto command and what it does:

| Command | What it does |
| ------- | ------------ |
| `plastic auto take ID [--allow-inline] [--harness NAME] [--agent NAME] [--model MODEL] [--thread ID]` | Arms the delivery lock of intent `ID` for this session and prints the lock and the code worktree. The flags record who delivers; under Claude Code the harness defaults to `claude`. From a conversation session, `take` refuses with exit 3 unless you pass `--allow-inline` with the owner's approval. |
| `plastic auto brief ID [--role ROLE]` | Prints the text that a spawned agent starts from. With `--role advisor`, it adds the advisor shapes. |
| `plastic auto report ID [--role ROLE]` | Prints the intent's completion report, then the rules for a review by risk. |
| `plastic auto lock status ID` | Prints who holds the delivery lock and how fresh it is. |
| `plastic auto lock fix ID` | Repairs a corrupt or old-format lock and prints what it did. |
| `plastic auto lock release ID` | Releases the lock. |

Every command takes `--json`. `plastic auto` alone lists the subcommands. An unknown intent
exits 1, and an unknown lock verb exits 2. A lock that belongs to another session exits 3:
`take` and `lock fix` refuse a held or stale lock, and `lock release` refuses a session that
does not own the lock. The refusal names `plastic auto lock status ID`, which shows the owner.
Reclaiming a stale lock is the owner's step.

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
