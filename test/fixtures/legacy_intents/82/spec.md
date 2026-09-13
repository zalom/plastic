# Spec: Insights timestamps and delivery

## Problem
The `## Insights` section is the durable, most-interesting residue of a cycle: short summaries of
what an agent discovered at any stage (What/Why/How/Exec), novel or old-but-newly-relevant, kept
for later reads. Two gaps undercut that purpose today:

1. **Entries carry only a date, not an exact time.** A bare `2026-06-22 (autonomous) ...` prefix
   records the day but not the precise capture moment, so nuggets cannot be located on the timeline,
   and the prefix says nothing about which stage or which agent surfaced the insight.
2. **Background/dispatched-agent insights are delivered inconsistently and sometimes dropped.**
   Insights discovered by background sessions and dispatched sub-agents land unreliably; a session
   that cannot write the intent file loses its nugget when the session ends. There is no single
   blessed path that guarantees both a uniform format and reliable persistence.

## Goals
- Prefix every `## Insights` entry with an exact UTC creation timestamp plus provenance, in a fixed,
  machine-parseable form.
- Reuse the savepoint ledger's exact timestamp convention so the store has one timestamp format.
- Make background/sub-agent insights ride home reliably so they can never be dropped.
- Provide one deterministic, tested write path (helper + validator) that agents and the orchestrator
  call instead of hand-editing.
- Codify the format, the definition of an insight, and the delivery rule on the agent-facing
  surfaces agents already read at spawn.

## Non-Goals
- **No backfill** of existing date-only entries. Going-forward only; fabricating past capture times
  would violate [[34]]'s append-only / immutability spirit. Existing entries stay exactly as written.
- **No doctor scan check** that audits entries for the prefix. That is a stretch follow-up, out of
  scope here.
- **No change to the savepoint ledger** itself; this intent only reuses its timestamp format.
- **No sub-second precision.** Second granularity matches the savepoint convention and is sufficient
  to order capture events.

## Approach
**Per-entry prefix `{utc-iso8601} · {stage} · {author}`.** Every `## Insights` entry leads with an
exact UTC timestamp plus provenance, e.g. `2026-06-24T08:13:05Z · Why · plastic-brainstorming
(autonomous)`. The `·` separator and field order are fixed so the prefix is machine-parseable by a
future doctor/index pass. This is a per-ENTRY prefix only: it does NOT change [[34]]'s ordering law.
Insights remain append-only, newest at the BOTTOM; the entry itself is never prepended to the top of
the section. The prefix sits at the head of each entry while the entry is still appended at the
bottom.

**Reuse the savepoint UTC ISO8601 format exactly.** The timestamp is `2026-06-24T08:13:05Z`,
identical to `Bridge.append_savepoint`'s output (UTC, ISO8601, to the second, `Z`). One timestamp
convention spans both ledgers, kept visually and mechanically consistent.

**Deterministic Ruby append helper (`insight-append`).** A `insight-append` CLI wraps a library
function that formats the prefix, validates it, and appends the entry at the bottom of `## Insights`
(creating the section if absent), never reordering existing entries. The library function takes a
DI'd `now:` seam exactly like `append_savepoint`. This is the blessed write path; agents and the
orchestrator call it instead of hand-editing. Hand-editing stays an escape hatch, but the helper is
the default so format drift cannot creep in.

**Pure format validator.** A deterministic library function recognizes a well-formed prefix
(returns true) and rejects a malformed one (returns false). It is the guard the helper applies on
write and is unit-tested in isolation with hermetic Minitest.

**Capture rides home in the [[74]] completion report.** Extend the [[74]] report contract with an
explicit `insights:` field carrying 0..N nuggets ("what I discovered worth keeping"). Background and
dispatched agents populate this field; the orchestrator (or any agent that can write the file)
persists each nugget on receipt via the helper. This is THE fix for dropped bg/sub-agent insights:
a background session that cannot write the intent file still returns its report, so the insight
survives as report payload and the orchestrator appends it. No insight depends on the discovering
session's write access.

**Codify on the agent-facing surfaces.** The rule lands on the surfaces agents already read at
spawn: PLASTIC.md's `## Insights` section (the format, what an insight is, and the bg/agent delivery
rule); the per-role payloads of `references/agent-report-contract.md`; and the `spawn-preamble`
REPORT_CONTRACT (the delivery mechanics, including the new `insights:` field).

## Alternatives Considered
- **Bare timestamp prefix (no stage/author)** — not chosen because a bare timestamp answers "when"
  but not "who/where"; merging stage and author into the prefix makes each nugget self-describing
  for later reads without changing the prose body.
- **A second, parallel delivery channel for bg/agent insights** — not chosen because the [[74]]
  completion report already carries structured payload home; adding a parallel mechanism duplicates
  plumbing and reintroduces the drop risk for sessions without file-write access.
- **Backfilling existing date-only entries to the new format** — not chosen because it would
  fabricate capture times that were never recorded, violating [[34]]'s append-only / immutability
  spirit.
- **A doctor scan that audits every entry for the prefix** — deferred as a stretch follow-up; the
  unit-tested validator shipped with the helper is sufficient for this intent.

## Decisions
- **Exact-timestamp prefix per entry** in the form `{utc-iso8601} · {stage} · {author}`, fixed
  separator and field order, refining the date-only prefix. Per-ENTRY prefix only; [[34]]'s ordering
  law (append-only, newest at the bottom, entry never prepended) is unchanged.
- **Reuse the savepoint UTC ISO8601 format exactly** (`2026-06-24T08:13:05Z`, to the second, `Z`),
  via the same DI'd `now:` seam as `Bridge.append_savepoint`. No sub-second precision. One timestamp
  convention across both ledgers.
- **Capture rides home in the [[74]] completion report**, not a parallel channel: extend the report
  contract with an `insights:` field (0..N nuggets); the orchestrator persists them on receipt so no
  insight depends on the discovering session's write access.
- **Deterministic `insight-append` helper + pure format validator** as the blessed write path; the
  helper formats the prefix, validates it, and appends at the bottom (creating the section if
  absent). Hand-edit remains an escape hatch.
- **Codify in PLASTIC.md + `references/agent-report-contract.md` + `spawn-preamble` REPORT_CONTRACT**
  — the surfaces agents read at spawn, so the rule takes effect through references.
- **No backfill** of existing date-only entries (going-forward only).

## Acceptance Criteria
- [ ] A library function appends a `## Insights` entry with the `{utc-iso8601} · {stage} · {author}`
      prefix at the BOTTOM of the section, creating the `## Insights` section if it is absent, and
      never reordering existing entries.
- [ ] The appended timestamp matches `Bridge.append_savepoint`'s UTC ISO8601 format exactly (to the
      second, trailing `Z`), and `now:` is injectable for deterministic output.
- [ ] A pure validator function returns true for a well-formed prefix and false otherwise.
- [ ] Hermetic Minitest covers: append-to-existing-section, append-when-section-missing, existing
      entry order preserved, deterministic timestamp via injected `now:`, and validator
      accept/reject. No eval, no global/ENV injection; tmpdir-isolated; single process.
- [ ] An `insight-append` CLI wraps the library function (args: intent_dir, text, `--stage`,
      `--author`) and is DI-friendly.
- [ ] The [[74]] report contract gains an `insights:` field on both the `spawn-preamble`
      REPORT_CONTRACT and the per-role payloads in `references/agent-report-contract.md`; role
      prompts instruct agents to populate it.
- [ ] PLASTIC.md's `## Insights` section documents the new prefix format, the definition of an
      insight, and the background/dispatched-agent delivery rule.

## Open Questions
None
