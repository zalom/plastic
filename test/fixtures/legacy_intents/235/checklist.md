# Checklist: Make the first install work on a clean Mac

Intent 235. Tier L. Seven actions plus seven standing verification items.

Worktree: `/Users/zlatko/apps/personal/plastic/.claude/worktrees/235--install-on-a-clean-mac`
Branch: `plastic/235--install-on-a-clean-mac`

Suite command (there is NO `Rakefile`, so `rake test` does not exist):

```
cd /Users/zlatko/apps/personal/plastic/.claude/worktrees/235--install-on-a-clean-mac
ruby -Itest -e 'Dir["test/*_test.rb"].each { |f| require File.expand_path(f) }'
```

## In Progress

(all items delivered, see Completed)

## Completed

### Actions

- [x] A1. `bin/plastic.js`: `RUBYOPT: ''` added after the `...process.env` spread, and the false
      "found not found" catch message replaced with an ENOENT branch plus a real error branch.
      Evidence: the scratch-HOME transcript under `PATH=/usr/bin RUBYOPT=--yjit` prints
      "found 2.6.10", and `grep "found not found" bin/plastic.js` is empty. (AC6)
- [x] A2. Nine bash hook launchers clear `RUBYOPT` at all 14 spawn sites with `env -u RUBYOPT`.
      Evidence: `bash -n` passes on all nine, the hooks scan reports zero offenders, and
      `scripts/hook-session-start` has zero changed lines. (G2, G4, AC9)
- [x] A3. Four ruby-side spawners clear `RUBYOPT` at all 9 spawn sites: `{"RUBYOPT" => nil}` as
      the leading env hash, `env -u RUBYOPT ruby` in the one backtick command.
      Evidence: `ruby -c` passes on all four and the ruby-side scan reports zero offenders. (G2)
- [x] A4. `scripts/lib/ruby_probe.rb` created, listed in the `InstallerCore` core-file map, and
      `test/ruby_probe_test.rb` green (7 tests), including the control test proving the fake
      interpreter is genuinely RUBYOPT sensitive. (AC5, AC12)
- [x] A5. `Doctor#check_ruby_runtime` added (`category: "runtime"`, `name: "ruby_floor"`, warn
      below floor, pass at or above, warn when undetermined), registered in `run_checks` only,
      `docs/internals.md` updated, `test/doctor_ruby_runtime_test.rb` green (8 tests). (AC8, AC12)
- [x] A6. `test/rubyopt_clearing_test.rb` created and green, now 9 tests after A10 below closed
      the count gap. Both negative controls were run and went red as expected: a reverted
      `hooks/bash-gate` and a throwaway new hook. Both reverted, `git status` clean. (AC4, AC12)
- [x] A7. `README.md` states the real Ruby requirement (3.0 or later, macOS ships 2.6, here is
      the mise command), and `scripts/lib/preflight.rb` confirmed at zero changed lines with
      `test/preflight_test.rb` green. (AC1)
- [x] A8 (post-A1-A7 fix, not in the original plan). `test/hermeticity_guard_test.rb`: added
      `NON_SPAWNING_SOURCE_SCANNERS` exemption for `rubyopt_clearing_test.rb`, a false positive
      in `test_every_bridge_writing_hook_spawn_isolates_its_tmp` (the scanner names hook paths
      and spawn-call tokens as text to detect, without ever spawning a process). Reported by a
      peer session's full-suite run, diagnosis independently confirmed by direct reading of the
      guard's source before applying the fix.
- [x] A9 (independent-review nit 1). Cleared `RUBYOPT` at two spawn sites the research table
      missed: `scripts/hash-intent:16` (inline `-e` call) and `scripts/migrate-to-global:47,71`
      (two heredoc invocations). Both ship in the npm tarball. Evidence: `bash -n` passes on
      both files; `env -u RUBYOPT` precedes `ruby` at all three sites; heredoc delimiters
      unchanged.
- [x] A10 (independent-review nits 2-5). `test/rubyopt_clearing_test.rb`: added a vacuity guard
      for the shell detector (recounts 14 recognized command words across `hooks/`); folded
      `ruby_spawn_line?` into the hooks scan so a Ruby-language hook (for example
      `Open3.capture3("ruby", ...)`) is caught by both detectors, verified red with a throwaway
      hook then removed; `plastic-rubyopt-exempt` now requires a colon plus a reason to exempt a
      line, verified a bare marker no longer exempts. `docs/internals.md`: the `ruby_floor`
      paragraph now names all three outcomes (pass, warn below floor, warn when undetermined),
      not two.

### Standing verification (run at the final gate, after A1 to A10)

- [x] V1. Full suite green in the worktree with the loader command above.
      Final: 1888 runs, 6794 assertions, 0 failures, 0 errors, 0 skips.
- [x] V2. Em-dash diff guard on ADDED lines only: printed "OK: no em-dash or en-dash in added
      lines". (AC10)
- [x] V3. Off-limits files carry zero changed lines: the grep printed nothing for
      `scripts/lib/(bridge|lock|worktree).rb`, `scripts/hook-session-start`,
      `scripts/codex-hook`. (AC7)
- [x] V4. No Spinel reference anywhere in the diff: grep printed nothing. (AC2)
- [x] V5. No auto-install code path: every `mise`/`mise.run` occurrence in the diff to
      `scripts/install.rb`/`bin/plastic.js` is inside a `console.error(...)` printed message,
      never a shell-out. (AC3)
- [x] V6. Bash 3.2 compatibility reviewed by eye on every changed shell file (the nine hook
      launchers): each edit is a single `env -u RUBYOPT` token insertion, no heredoc inside
      `$(...)`, no associative array, no `${var^^}`, no bash 4 feature; `bash -n` passed on all
      nine. (AC9)
- [x] V7. No commit on the branch carries AI attribution: the grep for
      `co-authored-by|generated with|assisted-by` over all 9 commit messages printed nothing.
      (AC11)

## Session Log

| Date | Items Completed | Notes |
|------|-----------------|-------|
| 2026-08-07 | A1-A8, V1-V7 | Executed all 7 planned actions plus one post-hoc fix (A8) for a hermeticity-guard false positive surfaced by a peer session's full-suite run. Full suite green: 1887 runs, 6793 assertions, 0 failures, 0 errors, 0 skips. 7 commits on `plastic/235--install-on-a-clean-mac`, working tree clean. |
| 2026-08-07 | A9, A10, V1-V7 re-verified | Independent review returned APPROVE WITH NITS (5 nits, no blocking defects). Fixed all five: 2 missed spawn sites (`hash-intent`, `migrate-to-global`), a vacuity guard gap and a language-coverage gap in the RUBYOPT regression test, a non-enforcing exemption marker, and a doc paragraph missing a check outcome. 2 more commits. Full suite green: 1888 runs, 6794 assertions, 0 failures, 0 errors, 0 skips. Working tree clean, 9 commits total on the branch. |
