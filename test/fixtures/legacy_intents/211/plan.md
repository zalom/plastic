# Plan: Generic Old-Intent Gap Handling + Amnesty Removal

Anchored to HEAD `7615108` on `main` (merge of `plastic/221a--hermetic-store-scan-tests`),
per `resources/discovery--legacy-gap-predicate.md`. Tier: M. Five actions, each independently
executable and reviewable; no project code ships outside these five.

## Goal
Replace `scripts/lib/legacy_bookend_amnesty.rb`'s shipped id-list allowlist with a generic,
per-store, runtime repairability predicate (219 D6), remove the amnesty file and every reader
of it, prove the founding no-personal-data-ships rule with a falsifiable packaging guard, and
wire the one legal repair (savepoint reconstruction) into 197's maintenance path. Leave the
44 live gaps in the owner's store untouched - this changes doctor's REPORTING only.

## Steps
- [ ] Step 1 (ACTION_1) - Rewrite `done_signal_findings_for_dir` and `check_done_signals` in
      `scripts/doctor.rb` around the generic predicate: `signals_complete` narrows to
      outcome-only and flips to `pass`; a new `savepoint_operational` check takes the
      operational bucket (missing savepoint.md entirely, or missing Done echo); the phantom-line
      amnesty suppression in `savepoint_truthful` is deleted outright (no replacement); `stalled_
      completion` and `signals_agree` are untouched.
- [ ] Step 2 (ACTION_2) - Delete `scripts/lib/legacy_bookend_amnesty.rb` and every reader:
      `doctor.rb`'s require, `LEGACY_BOOKEND_AMNESTY` constant, and the constructor's
      `bookend_amnesty:`/`@bookend_amnesty` seam; `installer_core.rb`'s `core_files` entry.
      No migration code needed (existing manifest-diff prune is already generic).
- [ ] Step 3 (ACTION_3) - Add `test/packaging_no_store_ids_test.rb`: derive the shipped-file set
      from `package.json`'s `"files"` array, scan for a frozen literal carrying 5+
      Folgezettel-shaped tokens, prove it via a reconstructed-amnesty-shape fixture (red,
      independent of the real file) and a real-shipped-tree scan (green, post-removal).
- [ ] Step 4 (ACTION_4) - Wire a fourth `maintenance-run --tool rebuild-savepoint --intent <id>`:
      same shape as the three existing tools (lock-checked, dry-run default, `MaintenanceGit.
      run_scoped` + `RevisionsWriter.append!`), composing `Bridge.rebuild_savepoint` +
      `Bridge.append_terminal_savepoint` with the disposition read only from `outcome.md`'s
      frontmatter; refuses if `outcome.md` is missing/placeholder.
- [ ] Step 5 (ACTION_5) - Rewrite the 5 DI-based `bookend_amnesty:` call sites in `test/doctor_
      done_signals_test.rb` (and the 2 tests whose premise - allowlist grandfathering - no
      longer exists) to assert the new check shapes directly; add one new fixture for the
      previously-uncovered "savepoint.md missing entirely" case.
- [ ] Verification - full suite green; `grep -rn "bookend_amnesty\|LegacyBookendAmnesty"` across
      `scripts/` and `test/` returns zero matches; `doctor --store plastic` (read-only, no
      `--apply`) run once to confirm the 44 surface under the new check names with zero store
      writes; em-dash diff guard on every authored/edited file.

## Notes
- No store writes anywhere in this delivery: the `doctor --store plastic` verification run in
  the final step is read-only (no `--fix`, no `--apply`); the 44 real intent directories in the
  owner's store are never touched.
- `rebuild-savepoint` is wired in Step 4 but never invoked against the owner's 44 gaps by this
  intent's Exec - that batch stays an explicit, separately owner-approved action (D8).
- 222's `check_intent_end`/`intent_links_projection_check_for` call `done_signal_findings_for_dir`
  too; Step 1 keeps the method's existing keyword-argument signature (including `scope:`, now
  unused internally) so that call site needs no change.
- Ordering matters only between Step 1 and Step 2 (the predicate rewrite must land before the
  amnesty file's require is deleted, or `doctor.rb` fails to load); Steps 3-5 are independent of
  each other and of Step 2's exact commit boundary, but all five land in the same delivery.
