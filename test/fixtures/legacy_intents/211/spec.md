Tier: M

# Spec: Generic Old-Intent Gap Handling + Amnesty Removal

## Problem
`scripts/lib/legacy_bookend_amnesty.rb` ships in the npm package today (`scripts/` is an
unfiltered `package.json` `"files"` entry, confirmed by `npm pack --dry-run`) and hardcodes one
user's own intent ids (3 global, 60 `project:plastic`) as a frozen `{scope => [ids]}` allowlist
that `doctor.rb`'s `done_signal_findings_for_dir` consults twice: to suppress a phantom-savepoint
warning (`savepoint_truthful`) and to suppress a missing-Done-echo gap (`signals_complete`), both
scoped to terminal (Completed/Abandoned) intents. This defines the fix for ONE store and ships
every other installer a snapshot of the owner's personal store, violating the owner's founding
rule that no maintenance artifact tied to personal/user-specific store data may ever ship in the
package. Separately, `signals_complete` today conflates two gap classes of different legal
character under one severity and one check name: a missing/placeholder `outcome.md` (a delivery
CLAIM, per 219 D6 never fabricated for a terminal intent) and a missing/incomplete `savepoint.md`
(an OPERATIONAL ledger, per 219 D6 minimally reconstructible). Treating both as one undifferentiated
`warn` bucket, suppressible only by a hand-maintained id list, is exactly the anti-pattern 219 D6
was written to retire. Finally, the one legal repair 219 D6 names (savepoint reconstruction) has
no wiring into 197's maintenance path (`maintenance-run` dispatches only
`project-links|rebuild-graph|restore-intent-v1` today), so even a willing owner has no scripted,
receipted way to run it.

## Goals
- Replace the id-list amnesty with a generic, per-store, runtime predicate that classifies every
  terminal-intent gap by repairability (219 D6), never by a shipped or hand-maintained id.
- Remove `scripts/lib/legacy_bookend_amnesty.rb` and every reader of it, proving the founding
  rule (no personal/user-specific store data ships) with a packaging guard that can fail.
- Give the one legal repair (minimal savepoint reconstruction) a scripted, receipted maintenance
  path, matching 197's `MaintenanceGit` + `RevisionsWriter` pattern.
- Leave the 44 live gaps in the owner's own store untouched; this intent changes REPORTING only.

## Non-Goals
- No batch repair of the 44 signals_complete gaps in the owner's store; `rebuild-savepoint` is
  wired but not invoked against them by this intent's Exec (owner-approval-gated per 197 D-batch).
- No doctor check for repo-distributable content; the packaging guard is a Minitest test
  (`test/`), matching `install_packaging_test.rb` precedent, not a new `doctor.rb` check
  category (219's three scopes are for an INSTALLED tree, not the distributable itself).
- No change to 222's intent-end close gate (`check_intent_end`) or its shared
  `done_signal_findings_for_dir` call site; 222 does not read `@bookend_amnesty` and stays
  unaffected by this predicate change beyond receiving the same, already-shared, per-dir findings
  hash with a new key.
- No new `outcome.md` reconstruction of any kind, at any tier; 219 D6 forbids it categorically.

## Approach
`done_signal_findings_for_dir` (`scripts/doctor.rb:676-741`) keeps its existing signature
(`scope:` kept for call-site compatibility with 222's `check_intent_end`, even though this method
no longer reads `@bookend_amnesty`) but its `findings` hash gains a fourth key,
`operational_gap:` (array, 0 or 1 strings), alongside the existing `gap:` (now outcome-only).
The classification is pure file-presence logic already visible on `dir`, requiring no injected
state: `gap` fires when `terminal && !outcome_real` (delivery-claim, unrepairable); `operational_gap`
fires when `terminal` and EITHER `savepoint.md` is missing entirely (a case the current code never
even checks) OR it exists but lacks the `Done delivered|abandoned` line (repairable, per 219 D6, by
`Bridge.rebuild_savepoint` + `Bridge.append_terminal_savepoint`). The phantom-line suppression
(`phantom_amnestied`) is deleted outright rather than replaced: a terminal phantom line was already
labeled "report-only (immutable history)" in its own message text, so the generic rule - every
terminal phantom is always advisory, never suppressed - is strictly more general than "terminal AND
on a frozen list," costs nothing, and needs no per-store state at all.

`check_done_signals` (`scripts/doctor.rb:743-846`) is restructured around two independent buckets
where today there is one. `signals_complete` keeps its name but narrows to the outcome-only bucket
and its severity flips from `warn` to `pass`: per the `check_skill_lint` precedent
(`scripts/doctor.rb:2789-2816`, "always status: pass ... informational only, never affects doctor's
exit code"), the message states the count and `details` lists each affected intent, but the status
can never be anything but `pass` because there is no legitimate fix action to hint at - 219 D6
forbids fabricating `outcome.md` unconditionally, so `fix_hint`/`fixable` are dropped entirely for
this check. A NEW check, `savepoint_operational`, takes the operational bucket: `warn`, `fixable:
true`, `fix_hint` pointing at `maintenance-run --tool rebuild-savepoint --intent <id> --apply`.
`savepoint_truthful` keeps its name, category, and `warn`-only severity (134's advisory ruling
stays intact) with the suppression branch simply deleted. `stalled_completion` and `signals_agree`
are untouched: neither reads `@bookend_amnesty` today and neither changes.

Amnesty removal is a straight deletion, not a replacement-with-empty-default: `scripts/lib/legacy_
bookend_amnesty.rb` is deleted; `doctor.rb`'s `require_relative "lib/legacy_bookend_amnesty"`
(line 29), the `LEGACY_BOOKEND_AMNESTY` constant (line 56) and its comment, and the constructor's
`bookend_amnesty:` keyword parameter plus `@bookend_amnesty` ivar (lines 98/101) are all deleted -
no DI seam survives, because the new predicate needs no injected suppression set. `installer_core.
rb`'s `core_files` entry for the file (line 361) is deleted. The already-installed copy at
`~/.plastic/scripts/lib/legacy_bookend_amnesty.rb` needs no separate migration: `installer_core.
rb:511-512`'s `old_files - new_files` manifest diff already prunes any file removed from
`core_files` on the next install/update, verified generic (not amnesty-specific) by reading
`prune_removed_files`'s two call sites.

The packaging guard is a new Minitest file, `test/packaging_no_store_ids_test.rb`, following
`install_packaging_test.rb`'s precedent of deriving the shipped set from reality (never a hand
list): it reads `package.json`'s own `"files"` array, expands every entry into the real file list
under the repo, and scans each file's content for a `%w[...]` or bracket-of-quoted-strings literal
carrying five or more Folgezettel-shaped tokens (`\A\d+[a-zA-Z0-9]*\z` - matches every real id
observed in the amnesty file: `1`, `121a`, `4a1c1`, `1b1a3`, etc.). Two assertions prove the 208
falsifiable-checks properties this guard must satisfy: (1) a fixture reconstructing the amnesty
file's exact shape must be caught (the RED case, run independent of whether the real file still
exists, proving the detector CAN report a problem); (2) the CURRENT shipped tree, scanned for
real, must carry zero such literals (the GREEN case - this is what actually goes from failing to
passing across this intent's own diff, since the amnesty file is deleted in the same delivery).
A file-by-file audit of every `.freeze`d `%w[]`/hash-of-arrays literal across `scripts/` (25+
found) confirms zero legitimate exemptions are needed: every other such literal in the shipped
tree uses letter-leading tokens (`plastic-statusline`, `delivered`, `SessionStart`) or bare short
words, none matching the digit-leading Folgezettel shape at the five-token threshold. Property (3)
of 208's doctrine ("fails open at runtime, loud in health check") applies loosely here since this
guard is a CI-time Minitest assertion, not a runtime doctor check - a failing assertion is
inherently loud in CI, matching the discovery's recommendation that this live as a test, not a new
`doctor.rb` check category.

`maintenance-run` gains a fourth `--tool rebuild-savepoint --intent <id>`, matching the exact
shape of the three existing tools (`run_project_links`/`run_rebuild_graph`/`run_restore_intent_v1`):
single-intent only, `check_not_fresh!` lock guard, dry-run by default, `--apply` required to write,
`MaintenanceGit.run_scoped` isolates the change to one scoped branch-then-merge commit, and
`RevisionsWriter.append!` records the receipt before the block returns. The reconstruction itself
composes the two already-shipped `Bridge` primitives with no new mechanical code:
`Bridge.rebuild_savepoint(dir)` rewrites `savepoint.md` from whichever lifecycle files are real on
disk, then `Bridge.append_terminal_savepoint(dir, disposition)` appends the Done bookend. The
disposition is read from `outcome.md`'s `disposition:` frontmatter only - never invented, matching
the 124a precedent already cited at `doctor.rb:841`'s fix_hint and `skills/intent-savepoint/
SKILL.md:53-56` - and the tool refuses loudly if `outcome.md` is missing or a placeholder, since
there is then nothing real to echo. Running it against the 44 stays an explicit, owner-approved,
future batch action; this intent only wires the tool.

Five DI-based tests in `test/doctor_done_signals_test.rb` (lines 29, 31-32, 231, 233, 245, 258,
273 per discovery) construct ad hoc `bookend_amnesty:` hashes; since the keyword is deleted from
`Doctor.new`, every one of those call sites is rewritten to assert the new check shapes directly
(no injected suppression axis survives to test).

## Alternatives Considered
| Alternative | Not chosen because |
|---|---|
| Replace the frozen id list with an empty default (`bookend_amnesty: {}`) and keep the DI seam | Still a hand-maintained id-shaped seam capable of being repopulated per store; the goal is a predicate with NO shipped or injectable id list, not a seam nobody currently fills. |
| Introduce a new doctor status value (e.g. `"pass-with-note"`) for the legacy bucket | `check_skill_lint` already establishes the exact precedent (status `"pass"`, count + details, informational, never affects exit code) using doctor's existing three-value status vocabulary; inventing a fourth value would touch every downstream status consumer for no behavioral gain. |
| Keep `signals_complete` as one check covering both gap classes, distinguished only in `details` text | `check()` returns one status per call; a single check cannot legitimately report both "pass, informational" (outcome) and "warn, fixable" (savepoint) simultaneously without conflating severities, which is the exact ambiguity 219 D6 exists to remove. |
| Make the packaging guard a new `doctor.rb` check category | 219's three doctor scopes (core, store scan, full project check) all diagnose an INSTALLED tree; verifying what the REPO would ship is a distinct, CI-time concern that `install_packaging_test.rb`'s existing precedent already owns as a Minitest suite. |
| Suppress terminal phantom lines by re-deriving a "pre-Bridge cutoff date" predicate instead of dropping suppression | There is no principled generic proxy for "this specific legacy intent is known to carry drift"; the check already labels terminal phantoms report-only, so dropping suppression (not replacing it) is the more generic, zero-state option and stays advisory either way. |
| Reconstruct `outcome.md` alongside `savepoint.md` when both are missing | 219 D6 forbids this categorically: `outcome.md` is a delivery claim, never inferred or fabricated, regardless of how plausible a stub would look. |

## Decisions
- D1: The generic predicate is a repairability classification computed at runtime from file
  presence alone (no injected or shipped id list): a missing/placeholder `outcome.md` on a
  terminal intent is a delivery-claim gap (unrepairable); a missing `savepoint.md` (entirely, a
  case not previously checked) or one missing the `Done delivered|abandoned` line is an
  operational gap (repairable). Non-terminal-intent gaps are untouched (222's close gate owns
  that surface).
- D2: `signals_complete` is repurposed to the outcome-only bucket, status flips from `warn` to
  always `pass` (matching `check_skill_lint`'s advisory precedent: count + details in message,
  no `fix_hint`/`fixable`, since fabricating `outcome.md` is never a legitimate fix).
- D3: A NEW check, `savepoint_operational`, takes the operational bucket (missing `savepoint.md`
  or missing Done echo): `warn`, `fixable: true`, `fix_hint` routes to `maintenance-run --tool
  rebuild-savepoint --intent <id> --apply`.
- D4: `savepoint_truthful` keeps its name and `warn`-only severity (134's advisory ruling intact)
  but drops id-based suppression outright - every terminal phantom line is now always advisory,
  never suppressed. `stalled_completion` and `signals_agree` are unchanged (neither ever read
  `@bookend_amnesty`).
- D5: `scripts/lib/legacy_bookend_amnesty.rb` is deleted along with every reader: `doctor.rb`'s
  require, `LEGACY_BOOKEND_AMNESTY` constant, and the constructor's `bookend_amnesty:`
  parameter/`@bookend_amnesty` ivar (no DI seam survives); `installer_core.rb`'s `core_files`
  registration entry is deleted. The already-installed copy needs no separate migration - the
  existing `old_files - new_files` manifest diff in `installer_core.rb` (verified generic, two
  call sites) prunes it on the next install/update.
- D6: The packaging guard is a new Minitest file (`test/packaging_no_store_ids_test.rb`), not a
  doctor check: it derives the shipped-file set from `package.json`'s own `"files"` array
  (never a hand list) and scans for a `%w[]`/bracket-of-quoted-strings literal carrying 5+
  Folgezettel-shaped tokens (`\A\d+[a-zA-Z0-9]*\z`). Proven via a fixture (RED, independent of
  the real file's existence) plus a real-shipped-tree scan (GREEN, post-removal). A full-tree
  audit of every `.freeze`d array/hash literal in `scripts/` found zero legitimate exemptions
  needed at the 5-token threshold.
- D7: `maintenance-run` gains a fourth tool, `rebuild-savepoint --intent <id>`, matching the
  existing three tools' shape exactly (single-intent, lock-checked, dry-run default,
  `MaintenanceGit.run_scoped` + `RevisionsWriter.append!` receipt). It composes
  `Bridge.rebuild_savepoint` + `Bridge.append_terminal_savepoint` with the disposition read only
  from `outcome.md`'s frontmatter (124a precedent); it refuses if `outcome.md` is missing or a
  placeholder.
- D8: Batch application of `rebuild-savepoint` against the owner's 44 live gaps is explicitly NOT
  run by this intent (owner-approval-gated per 197); this intent wires the tool only.
- D9: The five DI-based tests in `test/doctor_done_signals_test.rb` referencing `bookend_amnesty:`
  are rewritten to assert the new check shapes directly, with no injected suppression parameter
  anywhere in the test file.

## Acceptance Criteria
- [ ] `done_signal_findings_for_dir` returns a populated `operational_gap:` entry for a terminal
      intent whose `savepoint.md` is missing entirely (a fixture proving this case, previously
      uncovered, is now caught).
- [ ] `signals_complete` reports `status: "pass"` (never `"warn"`) with `details` naming each
      affected intent, for a terminal intent missing/placeholder `outcome.md` - proven by a
      rewritten fixture pinning the new severity.
- [ ] `savepoint_operational` reports `status: "warn"`, `fixable: true`, and a `fix_hint` naming
      `maintenance-run --tool rebuild-savepoint`, for a terminal intent missing the Done echo -
      proven by a fixture with no amnesty parameter passed anywhere.
- [ ] `savepoint_truthful` warns on a terminal phantom line even when the fixture's (scope, id)
      matches what would have been an amnestied pair under the old mechanism - proven by a
      fixture asserting no suppression occurs (the removed-suppression case, generic across
      every id).
- [ ] `Doctor.new` no longer accepts a `bookend_amnesty:` keyword; `grep -rn "bookend_amnesty\|
      LegacyBookendAmnesty"` across `scripts/` and `test/` returns zero matches.
- [ ] `scripts/lib/legacy_bookend_amnesty.rb` does not exist on disk; `installer_core.rb`'s
      `core_files` has no entry referencing it.
- [ ] The packaging guard's fixture test fails (catches the amnesty-shaped literal) when run
      against a reconstructed fixture carrying the old file's exact shape, proving the detector
      can report a problem (208 property 1) independent of the real file's current existence.
- [ ] The packaging guard's real-shipped-tree test passes clean against the post-removal repo
      (`package.json`'s `"files"` set, scanned for real) - this is the proof case: it would have
      failed against pre-removal `main` (the amnesty file, still shipped, matches the literal
      shape) and passes only because this intent's own diff removed it.
- [ ] `maintenance-run --tool rebuild-savepoint --intent <id>` (dry-run, no `--apply`) runs
      clean against a fixture terminal intent missing its Done echo, and refuses loudly against
      a fixture whose `outcome.md` is missing/placeholder.
- [ ] `doctor --store plastic` (read-only, no `--apply`, no `--fix`) against the owner's real
      store surfaces the 44 gaps under the new check names (`signals_complete` pass-with-count,
      `savepoint_operational` warn-with-count) with zero writes to any store - asserted by
      running the command and inspecting output only, never by editing a single one of the 44
      intent directories.
- [ ] Full test suite is green; zero em-dashes introduced in any authored file (intent-store or
      code) per the diff-guard convention.

## Open Questions
None.
