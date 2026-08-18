# Gate Enforcement and Stuck Detection

## Bridge File Pattern

`/tmp/plastic-{session}.json` is the hot cache; the filesystem is the authority.
SessionStart rebuilds the bridge file from the filesystem — the bridge is always disposable.

## Gate Taxonomy

| Gate type | Purpose |
|---|---|
| **Pre-flight** | Prerequisites exist? |
| **Revision** | New info invalidated prior work? |
| **Escalation** | Blocked items surface to user |
| **Abort** | Inconsistent state detected |

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

No automatic stuck detector ships today: no threshold fires, and nothing forces a savepoint
or escalates on its own. What exists is recorded data, and reading it is the diagnosing
agent's judgment:

- `build.gate_failures` in the bridge file: `scripts/hook-gate-check` increments it on every
  blocked write and resets it to 0 on a passing one. Nothing reads the counter back; a high
  value is a signal for you, not a trigger for the system.
- `build.last_activity` in the bridge file: updated on passing writes. There are no
  inactivity timers, and context pressure is not tracked anywhere.

When diagnosing, treat repeated denies of the same gate with no station progress (compare
the savepoint ledger) as stuck: stop, read the deny reason, and route through the resolving
command it names.
