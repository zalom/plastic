# Checklist: Restore-to-v1 preserves the frontmatter graph

## In Progress
(none)

## Completed
- [x] Task 1: Pure library `scripts/lib/restore_intent_v1.rb` (union + target resolution + apply)
- [x] Task 2: CLI shell `scripts/restore-intent-v1` (dry-run/apply, git extraction, reporting)
- [x] Task 3: The proof pair (old behavior loses the backlink, new tool preserves it)
- [x] Task 4: Target-resolution tests (dead edge dropped, dead+live combined), dry-run-default
      (zero filesystem writes), whole-directory revert (checklist/outcome/spec/plan to exact v1
      bytes), and Links preservation (## Links matches the preserved graph after --apply)
- [x] Task 5: Fail-loud tests (unresolved --at, unresolved id, unparseable frontmatter)
- [x] Task 6: Documentation edits (PLASTIC.md, skills/intent-creating/SKILL.md)
- [x] Task 7: Full suite green, em-dash guard, commit
- [x] Task 7b (found during AC verification, not in original action): registered
      scripts/restore-intent-v1 and scripts/lib/restore_intent_v1.rb in
      scripts/lib/installer_core.rb's core_files manifest (install_sync_test and
      installer_core_test failed without it)
- [x] Task 7c (found during AC verification): closed 4 gaps between the ACTION_1.md
      code and spec.md's Acceptance Criteria: (1) dry-run/apply report now prints the
      v1 graph, current graph, and union explicitly, plus any current-only edge (D3
      transparency), not only the union; (2) revisions.md entries now name the files
      reverted; (3) added a test proving the restored .md is byte-identical to the v1
      git blob outside the sources/chain lines and the derived ## Links section; (4)
      added tests proving exactly one revisions.md entry per restore, the dry-run
      report also names a dropped dead edge (not only --apply), and the --apply
      maintenance-lock reminder text appears.

## Session Log
| Date | Items Completed | Notes |
|------|-----------------|-------|
| 2026-07-14 | Tasks 1-7 + installer manifest fix + AC-gap closure | Full suite: 1476 runs, 5078 assertions, 0 failures, 0 errors. Em-dash guard on full diff vs main: clean. Manual dry-run fixture confirmed v1/current/union/current-only report lines print as spec.md requires. |
