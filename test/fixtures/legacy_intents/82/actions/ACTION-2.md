# ACTION-2 — Hermetic Minitest (`test/insights_test.rb`)

Implements acceptance criterion 4 (hermetic Minitest: append-to-existing, append-when-missing,
order preserved, deterministic via injected `now:`, validator accept/reject). Depends on ACTION-1.

## Where
Code worktree: `/Users/zlatko/apps/personal/plastic/.claude/worktrees/82--`
- NEW file: `test/insights_test.rb`

## What to build
Model the file on `test/savepoint_ledger_test.rb` (library-level Minitest with `Dir.mktmpdir`
isolation and injected `Time.utc(...)`). Header:

```ruby
require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "time"
require_relative "../scripts/lib/insights"
```

`setup` creates `Dir.mktmpdir`, an intent dir like `82--demo` with an intent file
`82--demo.md` (so `Bridge.intent_file` resolves); `teardown` `FileUtils.rm_rf`s the tmp root.
A fixed injected time: `T = Time.utc(2026, 6, 24, 8, 13, 5)` rendering `2026-06-24T08:13:05Z`.

Required test cases (one assertion-focused method each):
1. **append-to-existing-section** — intent file already has `## Insights` with one entry; after
   `Insights.append_insight(dir, "new nugget", stage: "How", author: "planner", now: T)` the file
   has BOTH entries, the new one LAST, with the exact prefix `2026-06-24T08:13:05Z · How · planner`.
2. **append-when-section-missing** — intent file has NO `## Insights`; after append, a
   `## Insights` heading exists and the entry sits under it.
3. **existing-order-preserved** — seed two entries A then B; append C; assert the section reads
   A, B, C in that order (no reordering, append-only).
4. **deterministic timestamp via injected `now:`** — two appends with the same injected `T`
   produce the identical prefix; assert the line contains `2026-06-24T08:13:05Z` exactly and no
   sub-second component.
5. **validator accept** — `assert Insights.valid_insight_prefix?("2026-06-24T08:13:05Z · Why · plastic-brainstorming (autonomous)")`.
6. **validator reject** — `refute` for: date-only `"2026-06-22 (autonomous) ..."`, missing
   separator `"2026-06-24T08:13:05Z Why me"`, missing `Z` `"2026-06-24T08:13:05 · Why · me"`, and
   sub-second `"2026-06-24T08:13:05.123Z · Why · me"`.

## Constraints
- Hermetic: `Dir.mktmpdir` only, no writes outside tmp. Single process (loaded by `bin/test`).
- DI: inject `now: T`; never read the wall clock in an assertion. No `eval`, no ENV / global seam.
- Ruby-first, Minitest (match the existing harness idioms in `test/savepoint_ledger_test.rb`).

## Verification
```
cd /Users/zlatko/apps/personal/plastic/.claude/worktrees/82--
ruby -Itest test/insights_test.rb
```
Expect all assertions green (0 failures, 0 errors). Then confirm discovery + full suite:
`ruby bin/test --list | grep insights_test` shows the file, and `ruby bin/test` stays green.
