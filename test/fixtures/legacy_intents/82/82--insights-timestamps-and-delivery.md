---
id: "82"
intent: "Improve the Insights section: prepend an exact creation timestamp to every insight entry, and tighten how background sessions and dispatched agents deliver insights (format plus delivery instructions)"
sources: []
chain: []
created: 2026-06-22
author: human
tags: ["project-plastic", "knowledge-graph", "insights", "convention", "harness", "background-agents"]
---

## Intent
Improve the Insights section: prepend an exact creation timestamp to every insight entry, and tighten how background sessions and dispatched agents deliver insights (format plus delivery instructions)

## Context
Surfaced 2026-06-22 while reviewing the autonomous `## Insights` entries written during the
49/72 store-graph maintenance. Two gaps in how Insights work today:

1. **Entry format.** Insights currently carry only a DATE prefix (e.g. `2026-06-22 (autonomous) ...`).
   The human wants an EXACT creation timestamp prepended to every entry, so the precise time each
   insight was captured is recorded, not just the day.
2. **Background-agent delivery.** Insights produced by background sessions and dispatched agents are
   delivered inconsistently. We need to tighten the delivery: a defined format plus explicit
   instructions so bg/sub-agents always record insights correctly and reliably.

### What Insights are (premise)

Insights are short, summarized messages of what an agent encountered at ANY stage of the Plastic
cycle (What/Why/How/Exec) — a discovery worth keeping available for later reads. The discovery may
be novel, or old-but-newly-relevant; either way it is insightful enough to retain. The human frames
the section as "the most interesting part of the intent." That framing drives both gaps: a precise
capture time makes each nugget locatable in the timeline, and a reliable delivery path makes sure
the nuggets bg/sub-agents find actually land in the file instead of evaporating with the session.

### Substrate the design reuses (researched)

- **Savepoint ledger timestamp format.** `Bridge.append_savepoint` already writes UTC ISO8601 to
  the second — the intent's own `savepoint.md` shows `2026-06-22T11:44:02Z`. The timestamp prefix
  reuses this EXACT format and the same DI'd `now:` seam, so the two ledgers stay visually and
  mechanically consistent and there is one timestamp convention in the store, not two.
- **Completion reports as the carrier ([[74]]).** Every dispatched agent already returns a
  structured completion report (intent 74; `spawn-preamble` REPORT_CONTRACT,
  `skills/auto/references/agent-report-contract.md`). This is the existing channel insights should
  ride home on, rather than a second parallel mechanism.
- **Ordering law ([[34]]).** Insights are append-only, newest at the BOTTOM, the ENTRY is never
  prepended to the top of the section. The new per-entry timestamp PREFIX must not be confused with
  prepending the entry; the prefix sits at the head of each entry while the entry itself is still
  appended at the bottom.
- **Codification surfaces ([[72]]).** PLASTIC.md plus the agent-facing references are the surfaces
  intent 72 just touched; the same surfaces (now also including 74's report contract) are where this
  rule gets codified so agents follow it through references.

### Constraints

- **Ruby-first.** The append helper and validator are Ruby.
- **Hermetic Minitest with DI.** Tests inject `now:` (mirroring `append_savepoint`); no eval, no
  global/ENV/config injection seam. Single-process, tmpdir-isolated.
- **Worktree split.** Code (helper, validator, references) lands in the code worktree; this design
  doc and its decisions land in the main store.

### Decisions (2026-06-22, human)

- **Exact-timestamp prefix per entry.** Every `## Insights` entry is prepended with an exact
  creation timestamp (the precise time that insight was created), refining the current date-only
  prefix. This is a per-ENTRY prefix; it does NOT change [[34]]'s hard ordering law (Insights stay
  append-only, newest at the bottom, the ENTRY is never prepended to the top of the section).
- **Tighten bg/agent insight delivery.** Define the insight entry format and the delivery
  instructions for background sessions and dispatched agents so insights are captured consistently
  and never dropped. Connects to [[74]]'s structured agent completion reports.
- **Codify the rule** in PLASTIC.md and the agent-facing references (same surfaces 72 just touched),
  so agents follow it through references.

### Decisions (2026-06-23, plastic-brainstorming, autonomous)

- **Structured per-entry prefix `{utc-iso8601} · {stage} · {author}`.** Every `## Insights` entry
  leads with an exact UTC timestamp plus provenance — e.g.
  `2026-06-24T08:13:05Z · Why · plastic-brainstorming (autonomous)`. Rationale: a bare timestamp
  answers "when" but not "who/where"; merging stage and author into the prefix makes each nugget
  self-describing for later reads (which stage surfaced it, which agent, whether autonomous) without
  changing the prose body. The `·` separator and field order are fixed so the prefix is machine-
  parseable by a future doctor/index pass.
- **Reuse the savepoint UTC ISO8601 format exactly (to the second, `Z`).** The timestamp is
  `2026-06-24T08:13:05Z`, identical to `Bridge.append_savepoint`'s output. Rationale: one timestamp
  convention across both ledgers; no sub-second precision because the savepoint ledger sets the
  existing convention and second-granularity is sufficient to order capture events.
- **Capture rides home in the [[74]] completion report, not a parallel channel.** Extend the report
  contract with an explicit `insights:` field carrying 0..N nuggets ("what I discovered worth
  keeping"); the orchestrator (or any agent that can write the file) persists them on receipt.
  Rationale: this is THE fix for dropped bg/sub-agent insights — a background session that cannot
  write the intent file still returns its report, so the insight survives as report payload and the
  orchestrator appends it. No insight depends on the discovering session's write access.
- **Deterministic append helper (`insight-append`).** A pure Ruby helper, DI'd `now:` like
  `append_savepoint`, formats the prefix, validates it, and appends the entry at the BOTTOM of
  `## Insights`. Agents and the orchestrator call the helper instead of hand-editing. Rationale:
  one blessed code path guarantees prefix-format consistency and bottom-append ordering; hand-edit
  stays possible as an escape hatch but the helper is the default so format drift cannot creep in.
- **Codify in PLASTIC.md + 74's report contract + spawn-preamble REPORT_CONTRACT.** The rule lands
  in PLASTIC.md's `## Insights` section (summary) and in the per-role payloads of
  `references/agent-report-contract.md` and the `spawn-preamble` REPORT_CONTRACT (the delivery
  mechanics). Rationale: agents pick up behavior through the references they already read at spawn,
  so the rule must live on those exact surfaces to take effect.

### Open questions — resolved

- **Timestamp format / precision** -> UTC ISO8601 to the SECOND (`2026-06-24T08:13:05Z`), matching
  the savepoint ledger. No sub-second component; matches the existing store convention.
- **Backfill existing date-only entries?** -> NO. Going-forward only. Backfilling would fabricate
  capture times that were never recorded and violate the append-only / immutability spirit of [[34]];
  existing date-only entries stay exactly as written.
- **Where do bg-delivery instructions live?** -> In the report contract (the `spawn-preamble`
  REPORT_CONTRACT plus the per-role payloads in `references/agent-report-contract.md`) AND summarized
  in PLASTIC.md's `## Insights` section.
- **doctor / test guard?** -> Ship a unit-tested format validator as part of the helper (deterministic,
  hermetic Minitest, DI'd `now:`). A doctor check that scans entries for the prefix is a
  stretch/follow-up, NOT required for this intent.

### Graph links this intent touches

These are relational `chain`-style connections (the intent reuses/honors these), not formative
`sources`:

- **[[34]]** — Insights ordering law. MUST honor: per-entry timestamp prefix != prepending the entry;
  entries stay append-only, newest at the bottom.
- **[[74]]** — Structured agent completion reports. The carrier this intent extends with an
  `insights:` field; the delivery fix depends on it.
- **[[72]]** — PLASTIC.md / reference surfaces. The codification target; same surfaces 72 touched,
  now plus 74's report contract.

(Spec stage: consolidate the above into spec.md — problem, the `insight-append` helper + validator
approach, the report-contract `insights:` field, the codification surfaces, and acceptance criteria
including a hermetic Minitest for the prefix validator. No open questions remain for the spec.)

## Outcome
Insights entries now carry a `{utc-iso8601} · {stage} · {author}` prefix, and bg/dispatched-agent insights ride home in the intent-74 completion report (new `insights:` field) and are persisted via the deterministic `insight-append` helper.

## Insights
2026-06-23T22:04:34Z · Why · plastic-brainstorming (autonomous) — The delivery fix and the format fix are the same lever: making each insight ride home as a structured `insights:` field on [[74]]'s completion report both guarantees a uniform `{utc-iso8601} · {stage} · {author}` prefix (the orchestrator formats it via one helper) AND stops bg/sub-agent insights from being dropped, because the nugget no longer depends on the discovering session's ability to write the file.
2026-06-23T22:26:44Z · Exec · plastic-executor (autonomous) — The code gate read the session bridge intent.dir, which was a malformed single-dash slug (82-insights-...) instead of the real double-dash store dir (82--insights-...); the gate could not find plan.md/checklist.md there and hard-blocked all code edits. Fixing intent.dir in the bridge JSON to the real folgezettel dir name unblocked it (gate then returned nil = How reached). Lesson: the code gate resolves How via the bridge-recorded intent dir, not the main store, so a bad intent.dir silently blocks Exec.
2026-06-23T22:26:53Z · Exec · plastic-executor (autonomous) — Adding scripts/lib/insights.rb tripped two regression guards from intent 78 in a single run: InstallerCoreTest (every scripts/lib/*.rb must be in InstallerCore#core_files) and InstallSyncTest (every script's require_relative lib must resolve to a manifested lib, since insight-append requires lib/insights). Both are satisfied by one manifest line. The CLI sibling itself (like agent-report) is not manifested; only the lib it requires must be.
2026-06-23T22:39:39Z · Exec · plastic-enforcer (autonomous) — Delivered and released as v1.0.0-beta.15 (npm beta dist-tag + GitHub Latest). The report-carried insights: field closed the loop: every specialist in this very cycle returned insights in its completion report, proving the bg/dispatched delivery path end-to-end.

## Links
<!-- No sources or chain; this intent has no graph edges to project. -->
