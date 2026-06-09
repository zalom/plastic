# Gate Enforcement and Stuck Detection

## Bridge File Pattern

`/tmp/plastic-{session}.json` is the hot cache; the filesystem is the authority.
SessionStart rebuilds the bridge file from the filesystem — the bridge is always disposable.

## Gate Taxonomy

| Gate type | Purpose |
|---|---|
| **Pre-flight** | Prerequisites exist? (e.g., spec.md before plan.md) |
| **Revision** | New info invalidated prior work? (e.g., Context changed after spec.md) |
| **Escalation** | Blocked items surface to user (e.g., unresolved decision needed) |
| **Abort** | Inconsistent state detected (e.g., outcome.md exists but checklist incomplete) |

## Transition Table

| Transition | Trigger |
|---|---|
| What → Why | `spec.md` written |
| Why → How | `plan.md` + `actions/` + `checklist.md` written (the triplet) |
| How → Exec | `checklist.md` has items to execute |
| Exec → Done | `outcome.md` written |

## Full Gate Enforcement

| Gate | Blocked action | Required prerequisite |
|---|---|---|
| Pre-flight | Cannot write `plan.md` | `spec.md` must exist |
| Pre-flight | Cannot create `actions/` | `spec.md` must exist |
| Pre-flight | Cannot write `outcome.md` | `checklist.md` must exist with all items checked |
| Revision | Cannot proceed to Exec | Context changed after spec.md — re-derive spec |
| Abort | Cannot complete intent | `outcome.md` exists but checklist has unchecked items |

Hard blocking — hooks exit with code 2 when gates fail.

## Stuck Detection

| Condition | Threshold | Action |
|---|---|---|
| Consecutive gate failures | 3+ | Warning |
| Consecutive gate failures | 5+ | Force savepoint + escalate to user |
| No activity | 5+ min | Warning |
| No activity | 10+ min | Force savepoint + escalate to user |
| Context pressure | 80% | Warning |
| Context pressure | 90% | Force savepoint |

Token tracking is done via transcript parsing — Claude Code hooks do not expose
token counts directly.
