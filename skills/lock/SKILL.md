---
name: plastic-lock
description: Inspect, repair, release, or reclaim an intent's delivery lock. Use when a lock-gate deny names /plastic-lock, when resuming interrupted work after a crash, reboot, or /tmp wipe, when a lock reads held or stale, or when the user says "fix the lock", "who holds the lock", or "reclaim the lock".
user-invocable: false
---

# Plastic Lock

Command-only wrapper around `~/.plastic/scripts/plastic-lock`. The durable
delivery lock is a `delivery.lock` file in the intent directory: ownership is
session-keyed, liveness is a lease (the owner's hooks refresh the file mtime;
stale means the heartbeat is older than the TTL). The /tmp bridge is only a
cache; the lock file wins every disagreement.

## Verbs

Run from the project (the intent resolves from this session's bridge), or pass
`--intent-dir` explicitly:

| Verb | What it does | When |
|---|---|---|
| `status` | Report the lock file, bridge cache, freshness, agreement | Always safe; run first |
| `fix` | Idempotent repair: rebuild lock + bridge from disk truth for THIS session. Never touches a fresh foreign lock | Interrupted work, corrupted state, /tmp wiped, legacy pid locks |
| `release` | Owner clears the lock | Ending or abandoning a boarding |
| `reclaim` | Explicit takeover of a STALE lock; appends an audit line to savepoint.md | The owner is gone and the lease expired |
| `delegate` | Owner registers a subagent session under the lock (`--delegate <session-id>`) | Auto-mode orchestration |

```
ruby ~/.plastic/scripts/plastic-lock status
ruby ~/.plastic/scripts/plastic-lock fix --intent-dir <store>/<id>--<slug>
ruby ~/.plastic/scripts/plastic-lock reclaim --intent-dir <store>/<id>--<slug>
ruby ~/.plastic/scripts/plastic-lock delegate --delegate <subagent-session-id>
```

## Rules

- `fix` exits non-zero when another session holds a FRESH lock: back off, do
  not retry in a loop. `status` shows the owner.
- `reclaim` refuses a fresh lock. There is no silent reclaim anywhere; every
  takeover is audited in the intent's savepoint.md.
- Acquiring a lock for new work is NOT this skill's job: board through
  `/plastic-intent-starting`, which calls the same repair internally.
