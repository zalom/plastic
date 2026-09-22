# Plan: Insights timestamps and delivery

## Goal
Give every `## Insights` entry an exact UTC creation timestamp plus provenance in the fixed,
machine-parseable form `{utc-iso8601} · {stage} · {author}`, reusing the savepoint ledger's
timestamp convention; provide one deterministic, tested write path (a Ruby library helper +
`insight-append` CLI + pure validator); and make background / dispatched-agent insights ride home
reliably by adding an `insights:` field to the [[74]] completion-report contract on the surfaces
agents read at spawn (spawn-preamble REPORT_CONTRACT, `references/agent-report-contract.md`,
PLASTIC.md). Going-forward only; no backfill, no doctor scan, no change to the savepoint ledger.

## Where the work lands

All code and references land in the code worktree
`/Users/zlatko/apps/personal/plastic/.claude/worktrees/82--` (branch `plastic/82--`). The
repo root `/Users/zlatko/apps/personal/plastic` has identical content; ACTION files use the
worktree path. Tests run via the in-repo single-process runner `bin/test` (and `bin/test --list`
to confirm discovery without a full run). This intent's design doc + decisions stay in the main
store; no store files are touched by Exec.

## Substrate the design reuses (verified against the code)

- **Timestamp format.** `Bridge.append_savepoint_line` writes `#{now.utc.iso8601}` which renders
  `2026-06-24T08:13:05Z` (UTC, ISO8601, to the second, trailing `Z`). The insight helper reuses
  this exact call so there is one timestamp convention across both ledgers.
- **DI'd `now:` seam.** `Bridge.append_savepoint(intent_dir, file_path, now: Time.now)` defaults
  `now:` and injects `Time.utc(...)` in tests. The insight helper mirrors this signature exactly.
- **Section-append style.** `## Insights` is a markdown section; entries are append-only, newest
  at the BOTTOM, the ENTRY is never prepended ([[34]]'s ordering law). The helper appends the new
  entry after the last line of the section, creating the section if absent, never reordering.
- **Test harness.** Minitest, hermetic, `Dir.mktmpdir` isolation, injected `now:`, single process
  via `bin/test`. Mirror `test/savepoint_ledger_test.rb` (library tests) and
  `test/agent_report_test.rb` (CLI shell-out tests).
- **Report contract single source of truth.** The `REPORT_CONTRACT` constant in
  `scripts/spawn-preamble` is authoritative; `references/agent-report-contract.md` and the role
  prompts (`agents/plastic-*.md`) reproduce it; `scripts/agent-report` approximates it.

## Steps

- [ ] **Step 1 (ACTION-1) — Library helper + validator.** Add `scripts/lib/insights.rb` with
      `Insights.append_insight(intent_dir, text, stage:, author:, now: Time.now)` (formats the
      `{utc-iso8601} · {stage} · {author}` prefix, validates it, appends one entry at the BOTTOM of
      `## Insights`, creating the section if absent, never reordering) and a pure
      `Insights.valid_insight_prefix?(line)` validator. Reuse the `now.utc.iso8601` format exactly.
      Verify: covered by Step 2's Minitest.
- [ ] **Step 2 (ACTION-2) — Hermetic Minitest.** Add `test/insights_test.rb` covering
      append-to-existing-section, append-when-section-missing, existing-order-preserved,
      deterministic timestamp via injected `now:`, and validator accept/reject. Verify:
      `ruby -Itest .../test/insights_test.rb` green, then full suite via `bin/test`.
- [ ] **Step 3 (ACTION-3) — `insight-append` CLI.** Add `scripts/insight-append` (sibling to
      `spawn-preamble`/`agent-report`) wrapping `Insights.append_insight`; args
      `<intent_dir> <text> --stage S --author A`. Verify: CLI shell-out test in `test/insights_test.rb`
      (mirroring `agent_report_test.rb`), green under `bin/test`.
- [ ] **Step 4 (ACTION-4) — Report-contract `insights:` field.** Add the `insights:` field to the
      `REPORT_CONTRACT` constant in `scripts/spawn-preamble`, to the common envelope + per-role
      payloads in `skills/auto/references/agent-report-contract.md`, and instruct agents to populate
      0..N nuggets in the role prompts; surface an insights line in `scripts/agent-report`. Verify:
      `test/spawn_preamble_test.rb` (update the verbatim REPORT_CONTRACT assertion) and
      `test/agent_report_test.rb` green under `bin/test`.
- [ ] **Step 5 (ACTION-5) — PLASTIC.md `## Insights` codification.** Update PLASTIC.md's Insights
      paragraph to document the `{utc-iso8601} · {stage} · {author}` format, the definition of an
      insight (a durable discovery at any stage, the most interesting part of the intent), the
      blessed write path (`insight-append`), and the bg/dispatched-agent delivery rule (insights
      ride home in the completion report; the orchestrator persists via the helper). No em-dashes /
      no AI tell-tales in this user-facing doc. Verify: `grep` for the format string and the
      delivery rule; full suite via `bin/test` still green.
- [ ] **Step 6 (suite-green) — Full suite green.** Run `bin/test` (single process, every test file
      loaded) and confirm 0 failures / 0 errors. Verify: `ruby bin/test` exits 0.

## Order rationale

Library first (1) so the tests (2) and the CLI (3) have something to call; the CLI wraps the same
library the tests already cover. The contract/doc steps (4, 5) are pure text surfaces that depend
only on the helper's existence and final names, so they come after the helper is named and tested.
Suite-green (6) is the final gate that proves nothing regressed. Steps 4 and 5 are independent of
each other and could run in either order, but both follow 1-3 because they reference the shipped
helper name (`insight-append`).

## Notes / constraints (binding on Exec)

- **Ruby-first.** Helper, validator, CLI, and tests are Ruby. No Python.
- **macOS bash 3.2 compat** for any shell used in verification: no heredocs inside `$(...)`, no
  bash 4 features (no associative arrays, no `${var^^}`). The CLI itself is Ruby, so this only
  bites verification commands.
- **No em-dashes** in any user-facing doc text (PLASTIC.md, the contract reference). Use a hyphen.
  Internal store/intent files are exempt, but the touched files here are user-facing.
- **Tests hermetic + DI.** Inject `now:` for determinism; isolate with `Dir.mktmpdir`; single
  process. No `eval`, no ENV / global-constant injection seam.
- **Honor [[34]].** The per-entry timestamp PREFIX is not prepending the entry; entries stay
  append-only, newest at the BOTTOM. The validator and helper must never reorder existing entries.
- **No backfill, no ledger change, no doctor scan** (explicit Non-Goals).
