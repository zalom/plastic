# ACTION-3 — `insight-append` CLI (`scripts/insight-append`)

Implements acceptance criterion 5 (a DI-friendly CLI wrapping the library helper). Depends on
ACTION-1; its test lands in `test/insights_test.rb` (ACTION-2's file).

## Where
Code worktree: `/Users/zlatko/apps/personal/plastic/.claude/worktrees/82--`
- NEW file: `scripts/insight-append` (executable Ruby, sibling to `scripts/spawn-preamble` and
  `scripts/agent-report`)
- EDIT: `test/insights_test.rb` (add a CLI shell-out test class/cases, mirroring
  `test/agent_report_test.rb`)

## What to build
A small Ruby CLI, same shape as `scripts/agent-report`:
```ruby
#!/usr/bin/env ruby
# encoding: UTF-8
# frozen_string_literal: true
require_relative "lib/insights"
```
- Parse args the way `agent-report` does (manual `while` loop, no optparse needed):
  positional `<intent_dir>` and `<text>`, flags `--stage S` and `--author A`.
- Usage error: if `intent_dir`, `text`, `--stage`, or `--author` is missing, `warn "usage: insight-append <intent_dir> <text> --stage S --author A"` and `exit 2`.
- On success: `Insights.append_insight(File.expand_path(intent_dir), text, stage: stage, author: author)`
  then print a one-line confirmation (e.g. the appended entry). Exit 0.
- `chmod +x scripts/insight-append` so it is executable like its siblings.
- DI-friendly: the CLI is a thin wrapper; the library's `now:` seam stays the test seam (the CLI
  itself uses the default `Time.now`, which is acceptable because determinism is tested at the
  library level in ACTION-2).

## CLI test (add to `test/insights_test.rb`)
Mirror `test/agent_report_test.rb`: `SCRIPT = File.expand_path("../scripts/insight-append", __dir__)`,
shell out via `IO.popen(["ruby", SCRIPT, intent_dir, "a nugget", "--stage", "How", "--author", "planner"], &:read)`.
- assert the intent file now contains a well-formed entry whose prefix passes
  `Insights.valid_insight_prefix?` and whose stage/author are `How` / `planner`.
- assert usage error + non-zero exit when `--stage`/`--author`/text is omitted (mirror
  `test_usage_error_without_intent_dir`).

## Constraints
- Ruby-first. macOS bash 3.2 only matters for the verification commands below (no heredocs in
  `$(...)`, no bash 4 features). The CLI is pure Ruby.
- Reuse `Insights.append_insight`; do not re-implement formatting or appending.

## Verification
```
cd /Users/zlatko/apps/personal/plastic/.claude/worktrees/82--
ruby -Itest test/insights_test.rb
```
The CLI cases pass green. Then `ruby bin/test` stays green.
