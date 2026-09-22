# ACTION-1 — Library helper + validator (`scripts/lib/insights.rb`)

Implements acceptance criteria 1, 2, 3 (the append behavior, the savepoint-format timestamp with
injectable `now:`, and the pure validator).

## Where
Code worktree: `/Users/zlatko/apps/personal/plastic/.claude/worktrees/82--`
- NEW file: `scripts/lib/insights.rb`

## What to build
Create a new module `Insights` in `scripts/lib/insights.rb`. Do NOT add this to `bridge.rb`; a
sibling library keeps the insight write path independent of the savepoint ledger (the spec
forbids touching the ledger). Two public methods:

### 1. `Insights.append_insight(intent_dir, text, stage:, author:, now: Time.now)`
- Build the prefix exactly as `{utc-iso8601} · {stage} · {author}` where the timestamp is
  `now.utc.iso8601` (identical to `Bridge.append_savepoint_line`, which renders
  `2026-06-24T08:13:05Z`). The separator is the middle dot `·` (U+00B7) with a single space on
  each side, field order timestamp, then stage, then author.
- Assemble the full entry line: `"#{prefix} — #{text}"` (an em-dash is fine HERE because the
  insight body matches the existing in-file convention shown in the intent's own `## Insights`
  entry; this is an internal store artifact, not user-facing doc text). Then assert
  `valid_insight_prefix?` returns true for the prefix; raise `ArgumentError` if it does not (guard
  on write).
- Append the entry at the BOTTOM of the `## Insights` section of `Bridge.intent_file(intent_dir)`:
  - If the file has a `## Insights` heading: insert the new entry after the last non-empty content
    line that belongs to that section (before the next `## ` heading or EOF), preserving every
    existing line and their order. Never prepend, never reorder ([[34]]'s ordering law).
  - If the file has NO `## Insights` heading: append a new `## Insights` section (a blank line, the
    `## Insights` heading, the entry) at the end of the file.
  - If the file does not exist: create it containing just the `## Insights` section + entry.
- Mirror `bridge.rb`'s style: small focused methods, `File.read` / `File.write`, no global state.
- DI: `now:` defaults to `Time.now`; tests inject `Time.utc(...)`. No ENV, no eval, no global
  constant seam.

### 2. `Insights.valid_insight_prefix?(line)` (pure)
- Returns `true` when `line` begins with a well-formed prefix:
  `{utc-iso8601 to the second, trailing Z} · {non-empty stage} · {non-empty author}`.
- Match the timestamp with a strict regex anchored at the start, e.g.
  `/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z · [^·]+ · [^·]+/`. Require both ` · ` separators and a
  non-empty stage and author segment.
- Returns `false` for a date-only prefix (`2026-06-22 (autonomous) ...`), a missing separator, a
  missing `Z`, or sub-second precision. Pure: no IO, no clock.

## Constraints
- Ruby-first. No Python. Reuse `now.utc.iso8601` verbatim (do not hand-format the timestamp).
- `require_relative "bridge"` to reach `Bridge.intent_file`; do not duplicate intent-file path logic.
- Honor [[34]]: append-only, newest at the BOTTOM, never reorder existing entries.

## Verification
Covered by ACTION-2's Minitest (`test/insights_test.rb`). After writing this file, a quick smoke:
`cd /Users/zlatko/apps/personal/plastic/.claude/worktrees/82-- && ruby -e 'require_relative "scripts/lib/insights"; puts Insights.valid_insight_prefix?("2026-06-24T08:13:05Z · Why · me")'`
should print `true` (and `... 2026-06-24 · Why · me` variant should be `false`). The authoritative
verification is ACTION-2 green under `bin/test`.
