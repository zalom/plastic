Tier: L

# Spec: Make the first install work on a clean Mac

## Problem

A clean Mac ships Ruby 2.6.10. Plastic's preflight gate (`scripts/lib/preflight.rb:19`,
`RUBY_FLOOR = "3.0.0"`) correctly refuses to run on it, so the first install stops at the very
first command a new user runs. That refusal message is the intended, honest behavior: 2.6 is
genuinely broken for Plastic (see Decisions, D1).

A second, sharper bug sits underneath the version check and makes even the honest message lie.
On a machine where the shell sets `RUBYOPT=--yjit` (common on machines that enable YJIT
globally), any bare `ruby` invocation with that flag crashes on Ruby 2.6, because `--yjit` is not
a recognized option there. `bin/plastic.js:47` calls `execFileSync('ruby', ...)` without clearing
`RUBYOPT`, so the child process crashes before it can print anything, and the `catch` block at
`bin/plastic.js` prints a hardcoded fallback: "Plastic needs Ruby 3.0.0 or newer to run its
scripts (found not found)." That message is false. Ruby was found. It crashed on the `RUBYOPT`
flag, not because it was missing. The same class of failure exists at every other point in the
codebase where Plastic spawns a `ruby` child process: 27 spawn sites across `hooks/`, `scripts/`
and `bin/plastic.js`, and none of them clear `RUBYOPT` today. A user chasing this message would
reasonably conclude Ruby is not installed, when the real fix is one environment variable.

## Goals

- G1: `Preflight::RUBY_FLOOR` stays at `3.0.0`, confirmed correct rather than changed.
- G2: Every in-scope ruby spawn site clears `RUBYOPT` before spawning, so a global
  `RUBYOPT=--yjit` (or any flag) never crashes a ruby child process that Plastic's install path
  or hooks launch.
- G3: Once `RUBYOPT` is cleared at `bin/plastic.js:47`, its failure message reports the true
  state (Ruby found, real version reported by preflight) instead of the current false
  "found not found" text.
- G4: `scripts/hook-session-start`'s two off-limits `RUBYOPT` spawn sites (lines 65, 142) are
  fixed transitively through the in-scope `hooks/session-start:9` launcher, with no edit inside
  the off-limits file.
- G5: `scripts/codex-hook`'s three off-limits `RUBYOPT` spawn sites (lines 71, 91, 107) are
  recorded as a documented, deliberate exclusion, handed to the codex-fixes roadmap.
- G6: One new doctor check reports which `ruby` binary the hooks would actually resolve on
  `PATH` and whether it meets `RUBY_FLOOR`.

## Non-Goals

- Lowering `RUBY_FLOOR` below `3.0.0`. A filtered suite run under real Ruby 2.6.10 produced 454
  errors and 54 failures out of 1707 runs; the floor stays where intent 38 set it.
- Adopting Spinel as a Ruby runtime or distribution mechanism. `matz/spinel` has zero releases,
  zero tags, one contributor, and no `fileutils`, `yaml`, `open3`, `digest`, `tempfile`,
  `rbconfig`, `timeout`, `cgi` or `rubygems` support, all of which Plastic's scripts need.
  Revisitable once Spinel has tagged releases and stdlib parity; not a one-way door closed by
  this intent.
- Auto-installing Ruby via mise during install. Piping `curl https://mise.run | sh` from inside
  an installer without asking first is a trust decision that belongs to the machine owner, and it
  would not even fix the underlying problem: `mise activate` rewrites `PATH` on shell prompt
  render, so it never reaches a hook process spawned directly by the Claude Code application.
- Editing `scripts/lib/bridge.rb`, `scripts/lib/lock.rb`, `scripts/lib/worktree.rb`,
  `scripts/hook-session-start`, `scripts/codex-hook`. All five are off limits to this intent (see
  the in-scope/off-limits file lists in Approach).
- Pinning an absolute Ruby interpreter path into the hook launchers, so hooks stop depending on
  `PATH` resolution at all. Deferred; see Follow-ups.
- Building any form of interpreter pinning or auto-repair inside the new doctor check. The check
  reports; it does not fix.

## Approach

Two independent fixes ship together because the owner ruled both must land in this intent: keep
the existing Ruby floor exactly as is, and clear `RUBYOPT` everywhere Plastic spawns a `ruby`
child process. A third, smaller addition closes the gap the research surfaced: a doctor check for
what `ruby` actually resolves to when a hook runs.

**The floor.** `Preflight::RUBY_FLOOR` stays `"3.0.0"`. No code change to the constant or its
guard tests in `test/preflight_test.rb`. The floor is correct: `Enumerable#filter_map` (Ruby
2.7+) is called at 17 sites across 9 files, `File.absolute_path?` (2.7+) at one more, and 2 of
those 9 files (`scripts/lib/bridge.rb`, `scripts/lib/lock.rb`) are off limits to this intent, so
even a deliberate attempt to lower the floor could not fully succeed inside this intent's
boundary.

**Clearing RUBYOPT.** The mechanism matters and is easy to get wrong: an env hash passed as the
first argument to `system`, `Open3.capture3`, `Process.spawn` or `IO.popen` MERGES onto the
inherited environment; it does not clear anything unless the key is present with a `nil` or
empty-string value. The fix at every in-scope site follows the language:
- Bash launchers: `env -u RUBYOPT ruby ...` (or `exec env -u RUBYOPT ruby ...` where the existing
  call already uses `exec`).
- `bin/plastic.js`: add `RUBYOPT: ''` to the env object passed to `execFileSync`.
- Ruby-side spawners (`system`, `Open3.capture3`, `IO.popen`): add `{"RUBYOPT" => nil}` (or
  `""`) as the leading env hash argument.

The in-scope file list, taken from the spawn-site table in
`resources/research--ruby-26-runtime-feasibility.md`:
- `bin/plastic.js` (line 47)
- `hooks/auto-arm` (lines 3, 5)
- `hooks/bash-gate` (line 3)
- `hooks/check-update` (line 31)
- `hooks/continue` (lines 4, 19)
- `hooks/edit-gates` (line 3)
- `hooks/future-intent-check` (lines 3, 23)
- `hooks/gate-check` (lines 4, 10, 15)
- `hooks/power-tools` (line 8)
- `hooks/session-start` (line 9)
- `scripts/link-suggest` (line 198)
- `scripts/maintenance-run` (lines 133, 142, 174, 203, 212)
- `scripts/restore-intent-v1` (line 274)
- `scripts/hook-continue` (lines 18, 39)

The off-limits file list, and why each is a non-issue or a documented exclusion:
- `scripts/lib/bridge.rb`, off limits, no ruby spawn sites relevant to RUBYOPT, holds two of the
  9 `filter_map`/`absolute_path?` floor-related hits (informational only, not touched).
- `scripts/lib/lock.rb`, off limits, same as above.
- `scripts/lib/worktree.rb`, off limits, spawns only `git`, never `ruby`, carries no RUBYOPT
  exposure at all, a non-issue rather than a gap.
- `scripts/hook-session-start`, off limits, has two backtick spawn sites (lines 65, 142). Fixed
  TRANSITIVELY: clearing `RUBYOPT` in the in-scope launcher `hooks/session-start:9` removes the
  variable from that ruby process's own environment, and every child process it spawns (including
  these two backticks) inherits the already-cleared environment. No edit inside the off-limits
  file is needed or made.
- `scripts/codex-hook`, off limits, owned by the codex-fixes roadmap, has three spawn sites
  (lines 71, 91, 107) that cannot be fixed from outside the file (an `Open3.capture3` call with
  its own env hash, and one `IO.popen` with no env hash at all). This intent records the gap and
  hands it to the codex-fixes roadmap; it is a scope handoff, not an owner decision to leave it
  broken.

**The bin/plastic.js message bug.** Once `RUBYOPT` is cleared at `bin/plastic.js:47`, the
`execFileSync` call stops crashing on `--yjit` under Ruby 2.6, so `ruby` actually runs and
`scripts/lib/preflight.rb` reports the true version. The `catch` block's hardcoded "found not
found" text should only fire when Ruby genuinely cannot be found or executed for a reason other
than RUBYOPT, not as the first line of defense it is today.

**The doctor check.** A hook spawned by the Claude Code application can still resolve bare `ruby`
on `PATH` to `/usr/bin/ruby` 2.6 even after the user installs Ruby 3.3 with mise, because mise
activation does not reach non-interactive spawned processes. Add exactly one new check to
`scripts/doctor.rb`, following the existing registry shape (`check(category:, name:, status:,
message:, details:, fixable:, fix_hint:)`), that reports which `ruby` the hooks would actually
resolve and whether it meets `RUBY_FLOOR`. The check reports only; it does not pin an interpreter
path or repair anything.

**Constraints that apply to every file this intent touches.** All shell must stay compatible with
macOS `/bin/bash` 3.2: no heredocs inside `$(...)`, no bash 4+ features. No added line anywhere
may contain an em-dash or en-dash. Commits carry no AI attribution.

## Alternatives Considered

| Alternative | Not chosen because |
|---|---|
| Lower RUBY_FLOOR to 2.6.10 (or test-and-lower to 2.7) | A filtered suite run under real Ruby 2.6.10 produced 1707 runs, 454 errors, 54 failures. filter_map (17 call sites, 9 files) and File.absolute_path? (1 site) have no 2.6 fallback, and 2 of the 9 affected files are off limits to this intent, so the floor could not be fully lowered even if chosen. Ruby 2.6 has been end of life since March 2022, making a lowered floor a permanent, unenforced tax on every future contribution with no CI job behind it. |
| Adopt Spinel (matz/spinel) as a runtime or distribution mechanism | Zero releases, zero tags, one contributor, no fileutils, yaml, open3, digest, tempfile, rbconfig, timeout, cgi or rubygems support. Nearly every Plastic script needs at least one of those. Revisitable once Spinel ships stdlib parity and cuts real versioned releases; not a closed door. |
| Auto-install Ruby via mise during install (silent or prompted) | Piping curl to sh from inside an installer is a trust decision that belongs to the machine owner, not a default code path. It also does not fix the problem by itself: mise activate rewrites PATH on shell prompt render, so it never reaches a hook process spawned directly by the Claude Code application; a robust fix would still need to resolve and pin an absolute interpreter path, which this intent defers (see Follow-ups). |

## Decisions

- D1: Keep `Preflight::RUBY_FLOOR` at `"3.0.0"`. Do not lower it to 2.6. Rationale: a filtered
  suite run under system Ruby 2.6.10 produced 1707 runs, 454 errors, 54 failures; `filter_map`
  (17 sites, 9 files, 2.7+) and `File.absolute_path?` (1 site, 2.7+) have no 2.6 fallback, and 2
  of the 9 affected files are off limits to this intent. Ruby 2.6 is end of life (March 2022)
  with no CI job to enforce continued compatibility. Intent 38 chose 3.0.0 on the `filter_map`
  evidence alone; this intent confirms 38 was right for a broader reason than 38 knew.
- D2: Do not adopt Spinel now. Rationale: `matz/spinel` has zero releases, zero tags, one
  contributor, and no implementation of `fileutils`, `yaml`, `open3`, `digest`, `tempfile`,
  `rbconfig`, `timeout`, `cgi` or `rubygems`, which nearly every Plastic script needs. Revisitable
  when Spinel has tagged releases and stdlib parity; not a one-way door.
- D3: Do not auto-install Ruby via mise during install in this intent. Rationale: this is the
  standard-boring-option ruling. The boring option is to keep the existing floor check and make
  its failure message perfect, roughly 90 percent already built in
  `scripts/lib/preflight.rb`. Auto-install is rejected on two grounds: piping `curl
  https://mise.run | sh` from inside an installer is a trust decision that belongs to the owner,
  not a default code path; and auto-install alone would not fix the problem, since `mise
  activate` rewrites PATH on shell prompt render and never reaches a hook process spawned by the
  Claude Code application.
- D4: Clear `RUBYOPT` at every in-scope ruby spawn site. Rationale: an env hash passed to
  `system`, `Open3.capture3`, `Process.spawn` or `IO.popen` MERGES onto the inherited
  environment and clears nothing unless the key is present with a `nil` or empty-string value.
  In bash the fix is `env -u RUBYOPT ruby ...`. In Node it is `RUBYOPT: ''` in the env object.
  The owner ruled this independently of the floor decision (D1): it is a distinct, sharper bug.
- D5: The off-limits scope conflict is mostly dissolved, with one documented carve-out.
  `scripts/hook-session-start`'s two backtick spawn sites (lines 65, 142) are fixed
  TRANSITIVELY by clearing `RUBYOPT` in the in-scope launcher `hooks/session-start:9`, because
  the variable is then absent from that ruby process's environment and its children inherit the
  cleared environment; no off-limits edit is needed. `scripts/codex-hook`'s three spawn sites
  (lines 71, 91, 107) cannot be fixed from outside the file; this intent records them as a
  deliberate, documented exclusion and hands them to the codex-fixes roadmap, a scope handoff,
  not an owner decision to leave them broken. `scripts/lib/worktree.rb` spawns only `git`, never
  `ruby`, so it carries no RUBYOPT exposure at all.
- D6: Add exactly one new doctor check that reports which `ruby` the hooks would actually
  resolve and whether it meets `RUBY_FLOOR`. Rationale: even after a user installs Ruby 3.3 with
  mise, a hook launched by the Claude Code application may still resolve bare `ruby` on `PATH`
  to `/usr/bin/ruby` 2.6, because mise activation does not reach non-interactive spawned
  processes. Doctor is the documented maintenance front door for this class of problem. Follow
  the existing registry shape in `scripts/doctor.rb`: `check(category:, name:, status:, message:,
  details:, fixable:, fix_hint:)`. One check only; no interpreter pinning.

## Acceptance Criteria

- [ ] AC1: `scripts/lib/preflight.rb` still defines `RUBY_FLOOR = "3.0.0"` (unchanged), verified
  by `test/preflight_test.rb` asserting fatal on `2.6.10` and clean on `3.0.0`/`3.3.5`.
- [ ] AC2: No code delivered by this intent references Spinel or adds a Spinel dependency,
  verified by inspecting the diff.
- [ ] AC3: Neither `scripts/install.rb` nor `bin/plastic.js` gains a code path that shells out to
  `curl https://mise.run` or runs `mise use`/`mise install` automatically; the existing
  instruct-only preflight message is preserved or improved, never replaced by an auto-install
  branch, verified by inspecting the diff.
- [ ] AC4: Every in-scope ruby spawn site named in the Approach's file list clears `RUBYOPT`
  before spawning, verified by a test that reads each in-scope launcher's source and asserts the
  clearing pattern is present (`env -u RUBYOPT` or equivalent in bash, an env hash carrying
  `"RUBYOPT" => nil` or `""` in Ruby spawners, `RUBYOPT: ''` in `bin/plastic.js`'s env object).
  The planner decides the exact test form; this criterion states the requirement.
- [ ] AC5: A hermetic test demonstrates the clearing mechanism works: an injected fake
  RUBYOPT-sensitive environment (dependency injected, no real `ENV` mutation) shows the cleared
  env hash reaching the child process call, mirroring the verified behavior that
  `Open3.capture3({"RUBYOPT" => nil}, "/usr/bin/ruby", "-v")` succeeds under a parent
  `RUBYOPT=--yjit` while the unmodified call crashes.
- [ ] AC6: After `RUBYOPT` is cleared at `bin/plastic.js:47`, the `catch` block's message no
  longer reads "found not found" for a RUBYOPT-caused crash; the real preflight message (naming
  the actual found Ruby version) is what prints instead, verified by test or transcript.
- [ ] AC7: `scripts/hook-session-start` and `scripts/codex-hook` carry zero changed lines in this
  intent's diff, verified by inspecting the diff for those two paths.
- [ ] AC8: One new check exists in `scripts/doctor.rb` reporting the resolved `ruby` binary and
  whether it meets `RUBY_FLOOR`, built with the existing `check(category:, name:, status:,
  message:, details:, fixable:, fix_hint:)` shape, verified by a hermetic Minitest that
  dependency-injects the ruby-resolution probe and asserts both a below-floor and an
  at-or-above-floor case.
- [ ] AC9: No shell script added or edited by this intent uses a heredoc inside `$(...)` or any
  bash 4+-only feature, verified by manual review of the diff against macOS `/bin/bash` 3.2
  compatibility.
- [ ] AC10: No added line in the diff contains an em-dash or en-dash character, verified by a
  diff-guard scan at the final gate.
- [ ] AC11: No commit in the delivered branch carries AI attribution (`Co-Authored-By` or
  equivalent), verified by inspecting each commit message.
- [ ] AC12: All tests added for this intent run hermetically under Minitest with constructor
  dependency injection: no `eval`, no `ENV` or global config seam, no live API calls, no network,
  verified by review of the added test files.

## Open Questions

None

- Whether a runtime test of Plastic under real Ruby 2.6/2.7 existed anywhere: resolved by D1
  (the filtered 2.6.10 suite run, 1707 runs / 454 errors / 54 failures, recorded in `##
  Insights`).
- Whether `RUBYOPT` should be cleared once at a shared entry point instead of per-launcher, given
  intent 244's dispatcher shape: resolved by D4 and D5 (clear at each in-scope spawn site per the
  file list; the transitive fix at `hooks/session-start:9` is the one place a single clear
  reaches multiple spawn sites, because they share a process tree, not because of a shared Ruby
  library entry point).
- Whether 235 should sequence after sibling intent 248's plugin-vs-direct-install verdict:
  resolved as no for this intent's RUBYOPT-clearing and doctor-check work, which proceeds now;
  only the absolute-interpreter-pinning follow-up waits for 248 (see Follow-ups).
- Whether 234 needs a scope correction now that intent 244 deleted its named target file:
  resolved as out of scope for 235, belongs to 234's own owner, not resolved here.
- Whether "bundle a Ruby with the installer" is compatible with mise activation not reaching
  non-interactive hook runners: moot, resolved by D3 (auto-install/bundling is rejected for this
  intent).

## Follow-ups

- Pin an absolute Ruby interpreter path into the hook launchers, so hooks stop depending on
  `PATH` resolution entirely (the doctor check in D6 only reports the risk; it does not fix it).
  This should become its own intent, sequenced AFTER sibling intent 248 rules on plugin-shaped
  versus direct install, because 248's verdict may relocate where hook launchers live and an
  interpreter-pinning fix written against today's launcher paths could need rework once 248
  lands. Non-blocking for this intent; the orchestrator judged it a follow-up, not a gap in this
  spec.
