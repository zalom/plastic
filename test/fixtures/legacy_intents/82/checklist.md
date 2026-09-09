# Checklist: Insights timestamps and delivery

One checkbox per action plus the suite-green gate. Each action is self-contained in
`actions/ACTION-N.md`. Acceptance criteria (AC) from `spec.md` are mapped per item.

## In Progress

- [x] **ACTION-1 — Library helper + validator** (`scripts/lib/insights.rb`) — AC 1, 2, 3
  - [x] `Insights.append_insight(intent_dir, text, stage:, author:, now: Time.now)` formats
        `{utc-iso8601} · {stage} · {author}` via `now.utc.iso8601` (savepoint format), validates,
        appends at the BOTTOM of `## Insights`, creates the section if absent, never reorders
  - [x] `Insights.valid_insight_prefix?(line)` pure validator (accept well-formed, reject
        date-only / missing separator / missing `Z` / sub-second)
  - [x] DI `now:` seam; no eval, no ENV / global injection

- [x] **ACTION-2 — Hermetic Minitest** (`test/insights_test.rb`) — AC 4
  - [x] append-to-existing-section, append-when-section-missing, existing-order-preserved
  - [x] deterministic timestamp via injected `now:`; validator accept + reject
  - [x] `Dir.mktmpdir`-isolated, single process; `ruby -Itest test/insights_test.rb` green

- [x] **ACTION-3 — `insight-append` CLI** (`scripts/insight-append`) — AC 5
  - [x] CLI wraps `Insights.append_insight`; args `<intent_dir> <text> --stage S --author A`;
        usage error + non-zero exit on missing args; executable bit set
  - [x] CLI shell-out test added to `test/insights_test.rb` (mirrors `agent_report_test.rb`), green

- [x] **ACTION-4 — Report-contract `insights:` field** — AC 6
  - [x] `REPORT_CONTRACT` constant in `scripts/spawn-preamble` names the `insights:` field
  - [x] common envelope + per-role payloads in `references/agent-report-contract.md` carry it;
        delivery rule (orchestrator persists via `insight-append`) documented
  - [x] role prompts (`agents/plastic-*.md`) instruct agents to populate `insights:`
  - [x] `scripts/agent-report` surfaces an insights line (pure function, no clock)
  - [x] `test/spawn_preamble_test.rb` REPORT_CONTRACT assertion updated; spawn-preamble +
        agent-report tests green

- [x] **ACTION-5 — PLASTIC.md `## Insights` codification** — AC 7
  - [x] documents the `{utc-iso8601} · {stage} · {author}` format + savepoint-format reuse
  - [x] documents the definition of an insight (durable discovery at any stage; most interesting
        residue) and that the per-entry prefix is not prepending the entry
  - [x] documents the blessed write path (`insight-append`) and the bg/dispatched-agent delivery
        rule (insights ride home in the report; orchestrator persists via the helper)
  - [x] no em-dashes / no AI tell-tales in the edited copy

- [x] **Suite-green gate** — `ruby bin/test` exits 0 (every test file loaded, single process; 0
      failures / 0 errors)

## Completed
(move items here when done)

## Session Log
| Date | Items Completed | Notes |
|------|-----------------|-------|
