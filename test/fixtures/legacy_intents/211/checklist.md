# Checklist: Generic Old-Intent Gap Handling + Amnesty Removal

## In Progress
(none)

## Completed
- [x] ACTION_1 - Rewrite `done_signal_findings_for_dir` + `check_done_signals` (generic
      predicate; `signals_complete` narrows + flips to pass; new `savepoint_operational`; drop
      phantom-line amnesty suppression)
- [x] ACTION_2 - Delete `scripts/lib/legacy_bookend_amnesty.rb` + every reader (doctor.rb
      require/constant/constructor seam, installer_core.rb core_files entry)
- [x] ACTION_3 - Add `test/packaging_no_store_ids_test.rb` (fixture red case + real-shipped-tree
      green case, derived from package.json's own "files" array)
- [x] ACTION_4 - Wire `maintenance-run --tool rebuild-savepoint --intent <id>` (composes
      `Bridge.rebuild_savepoint` + `Bridge.append_terminal_savepoint`, 197-conformant receipt);
      added 7 hermetic fixture tests to `test/maintenance_run_test.rb` (dry-run, apply +
      one revisions.md entry, missing/placeholder outcome refusal, fresh-lock defer)
- [x] ACTION_5 - Rewrote the 5 DI-based `bookend_amnesty:` tests + added 1 new fixture
      (savepoint.md missing entirely) + deleted 2 now-redundant tests in
      `test/doctor_done_signals_test.rb` (15 -> 14 tests, net -1 as specified)
- [x] Verification - `grep -rn "bookend_amnesty\|LegacyBookendAmnesty"` across `scripts/` and
      `test/` returns zero matches (one deviation noted: the mandated verbatim fixture in
      `test/packaging_no_store_ids_test.rb` necessarily embeds the literal string to prove the
      detector catches it; see Insights)
- [x] Verification - full test suite green: 1837 runs, 6406 assertions, 0 failures, 0 errors,
      0 skips
- [x] Verification - `doctor --store plastic` run read-only (no `--fix`, no `--apply`); new
      check names surface `signals_complete` pass/33, `savepoint_operational` warn/111 (higher
      than the old 44 because the new predicate also catches savepoint.md missing entirely, a
      case never checked before); zero writes to any store (doctor.rb has no File.write/
      FileUtils calls at all; confirmed by source grep)
- [x] Verification - em-dash diff guard: zero em-dashes introduced on any added line across
      all touched/new files

## Session Log
| Date | Items Completed | Notes |
|------|-----------------|-------|
| 2026-07-19 | ACTION_1-5 + all Verification items | Exec by plastic-executor (autonomous); full suite green; RED-then-GREEN packaging guard proof captured naming the file |
