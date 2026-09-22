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
- [x] Task 8 (independent review round, 2 blocking + 5 required fixes): prose
      siblings now restore against what existed AT the v1 ref, not what exists NOW
      (a deleted checklist.md was silently never restored); resolve_union now
      writes GraphRebuild's RESOLVED value (classification[:id]/[:ref]) instead of
      the stale pre-resolution ref; the graph-write confirmation now re-parses the
      written content and asserts it equals the computed union instead of a weak
      substring check; find_intent_dir aborts loud naming every candidate on a
      cross-store bare-id collision instead of guessing the first match; a dead,
      misleading assertion line was removed from the centerpiece proof-pair test;
      --apply now announces the store-wide ## Links reprojection blast radius and
      accepts --skip-links to decline it with a loud staleness warning; added a
      CLI-level test proving `sources` (not only `chain`) survives a restore;
      amended spec.md's Approach to remove the unimplemented doctor.rb I1
      post-hoc-cross-check sentence. 6 new tests (19 total in the integration
      file, 7 in the lib file).

## Session Log
| Date | Items Completed | Notes |
|------|-----------------|-------|
| 2026-07-14 | Tasks 1-7 + installer manifest fix + AC-gap closure | Full suite: 1476 runs, 5078 assertions, 0 failures, 0 errors. Em-dash guard on full diff vs main: clean. Manual dry-run fixture confirmed v1/current/union/current-only report lines print as spec.md requires. |
| 2026-07-14 | Task 8: independent-review fix round (2 blocking + 5 required) | Full suite: 1484 runs, 5115 assertions, 0 failures, 0 errors. Em-dash guard on the fix diff: clean. Commit b45af08. |
