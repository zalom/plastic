# Plan: Make the first install work on a clean Mac

Tier: L. One action file per task, each self-contained.

## Goal

Two fixes and one new report, from spec.md:

1. Keep `Preflight::RUBY_FLOOR` at `"3.0.0"` (confirm, do not change).
2. Clear `RUBYOPT` at every in-scope ruby spawn site, so a global `RUBYOPT=--yjit` can never
   crash a ruby child process that Plastic launches, and so `bin/plastic.js` stops printing
   "found not found" when Ruby was in fact found.
3. Add one doctor check that reports which `ruby` a spawned hook would resolve on `PATH` and
   whether it meets the floor. Report only, no repair.

## Where the work happens

- Code worktree (all edits): `/Users/zlatko/apps/personal/plastic/.claude/worktrees/235--install-on-a-clean-mac`
- Branch: `plastic/235--install-on-a-clean-mac`
- Intent store (no code): `/Users/zlatko/.plastic/projects/plastic/store/235--install-on-a-clean-mac`

## Steps

- [ ] ACTION_1 - `bin/plastic.js`: add `RUBYOPT: ''` to the `execFileSync` env object and replace
      the false "found not found" catch message with an honest one.
      Verify: real transcript run under `PATH=/usr/bin` plus `RUBYOPT=--yjit` against a scratch
      `HOME` prints preflight's true message naming Ruby 2.6.10. Satisfies AC6, keeps AC2/AC3.
- [ ] ACTION_2 - nine bash hook launchers under `hooks/`: 14 spawn sites get `env -u RUBYOPT`
      in front of `ruby`.
      Verify: `bash -n` on each file, plus a grep that every `ruby` token is preceded by the
      clearing form. Satisfies G2, G4, AC9.
- [ ] ACTION_3 - four ruby-side spawner scripts: `scripts/link-suggest`, `scripts/maintenance-run`,
      `scripts/restore-intent-v1`, `scripts/hook-continue`. Nine spawn sites get a leading
      `{"RUBYOPT" => nil}` env hash, or `env -u RUBYOPT ruby` inside the one backtick command.
      Verify: `ruby -c` on each file plus the existing suite. Satisfies G2.
- [ ] ACTION_4 - new `scripts/lib/ruby_probe.rb` (pure, injectable), registered in
      `InstallerCore`'s core-file map, plus `test/ruby_probe_test.rb`.
      Verify: `ruby -Itest test/ruby_probe_test.rb` green, plus `test/install_sync_test.rb`.
      Satisfies AC5, AC12.
- [ ] ACTION_5 - new doctor check `runtime` / `ruby_floor` in `scripts/doctor.rb`, registered in
      `run_checks`, plus `test/doctor_ruby_runtime_test.rb` and a one-line `docs/internals.md`
      update.
      Verify: `ruby -Itest test/doctor_ruby_runtime_test.rb` green. Satisfies AC8, AC12.
- [ ] ACTION_6 - new `test/rubyopt_clearing_test.rb`: the source-scan regression test that
      enumerates `hooks/*` and the named ruby-side spawners and fails on any uncleared spawn.
      Verify: green after ACTION_1 to ACTION_3, and red if any one of those edits is reverted.
      Satisfies AC4.
- [ ] ACTION_7 - install docs: fix the false Ruby requirement claim in `README.md`, and confirm
      `scripts/lib/preflight.rb` carries zero changed lines.
      Verify: `git diff` on preflight is empty and `test/preflight_test.rb` is green.
      Satisfies AC1.

## Order and independence

Order is forced in only two places:

- ACTION_6 must run after ACTION_1, ACTION_2 and ACTION_3, because it is the test that asserts
  their result. Written earlier it would be red for the whole delivery.
- ACTION_5 must run after ACTION_4, because the doctor check calls `RubyProbe.resolve` as its
  default probe.

Everything else is independent. ACTION_1, ACTION_2 and ACTION_3 touch three disjoint file sets
(one JS file, nine bash files, four ruby scripts) and share no symbol. ACTION_7 touches only
`README.md` and reads `preflight.rb`. A fresh executor can run 1, 2, 3, 4 in any order, then 5,
then 6, then 7.

## Design decisions this plan makes

### D-P1: the AC4 regression test uses neutralize-then-scan, not pattern matching

The test does not try to write a regex that recognizes a spawn site. It does the reverse:

1. Take a source line. Skip it if it is a comment or carries the exemption marker.
2. Replace every occurrence of the CLEARED form with a placeholder word.
3. Assert that no spawn token survives.

For a shell file the cleared form is the literal string `env -u RUBYOPT ruby ` and the spawn
token is the bare word `ruby` followed by whitespace, not preceded by a word character, a dot, a
slash or a hyphen. Uppercase `RUBYOPT` never matches the lowercase token, and `-rjson` or a path
ending in `hook-continue` never matches either.

This gives the property we actually want: a NEW hook added later that types `ruby` without
clearing is caught automatically, because the scan enumerates `hooks/*` rather than a hardcoded
list. No maintainer has to remember to add the new hook to a test.

Known limit, recorded on purpose: the rule targets the bare-name form (`ruby ...`), which is
every spawn site Plastic has today. An absolute-path launcher (`/opt/ruby/bin/ruby ...`) would
not match. That form arrives only with the deferred interpreter-pinning follow-up named in
spec.md, and that intent must widen this rule. The test file says so in a comment.

### D-P2: the exclusion list for the `hooks/*` enumeration is empty, by design

Candidate exclusions and why none is needed:

| File | Spawns ruby | Needs an exclusion entry |
|---|---|---|
| `hooks/hooks.json` | No, it is JSON data | Yes, one: skip `*.json`, it is not a script |
| `hooks/run-hook` | No. It `exec`s a sibling hook BY PATH and relies on that file's shebang | No. It contains no `ruby` token, so it passes the scan trivially |
| `hooks/savepoint` | No. Pure bash, prints a JSON heredoc | No. Same reason |
| `hooks/statusline` | No. Pure bash by design, its own header says "no ruby, no jq" | No. The word ruby appears only in a comment, and comments are skipped |

So the only exclusion in the test is "files ending in `.json`", and it is there because JSON is
not a shell script, not because that file is a tolerated gap. Three files that a naive list
would have excluded need no entry at all, which is the point: they are checked, and they pass.

A future maintainer with a genuinely legitimate uncleared spawn adds the marker
`# plastic-rubyopt-exempt: <reason>` on that line. The marker is per line, requires a written
reason, and is greppable. It is documented in the test file and unused today.

### D-P3: the ruby-side half of the AC4 test is a named list, not a sweep

`hooks/*` is safe to enumerate. `scripts/*` is not: it holds 60 or more files that spawn `git`,
`npm` and other programs, and two off-limits files (`scripts/codex-hook`,
`scripts/hook-session-start`) that legitimately still carry uncleared ruby spawns per D5 in
spec.md. A blanket `scripts/*` sweep would either fail on the off-limits files or need an
exclusion list longer than the assertion.

So the ruby half names the four in-scope files, and a comment block in the test records the two
off-limits files and their line numbers as known, deliberate gaps handed to the codex-fixes
roadmap. The record lives in a comment, not an assertion, because asserting a gap would make the
test fail the day the codex-fixes roadmap closes it.

Discriminator for a ruby-side spawn site: the line contains one of `system(`, `Open3.capture3(`,
`IO.popen(`, `Process.spawn(` AND references a ruby interpreter (`RbConfig.ruby` or the literal
`"ruby"`); OR the line holds a BALANCED backtick pair whose command starts with `ruby` (after an
optional `env -u RUBYOPT`). A `system(...)` call that spawns git is not a ruby spawn site and is
not flagged. Cleared means the same line carries `"RUBYOPT" =>` or `env -u RUBYOPT ruby`.

The balanced-pair requirement is not decoration. `scripts/restore-intent-v1:207` is a user-facing
warning string that contains a single, unmatched backtick followed by the word ruby
(`"Rerun \`ruby #{...} --plastic-home "`, closed two lines later). A naive backtick rule flags it
as an uncleared spawn and the test fails on prose. Requiring an even backtick count of at least
two on the line drops it, because a real backtick command literal in these files is always
balanced on its own line. Verified against the current sources: the rule finds exactly 9 sites
(link-suggest 1, maintenance-run 5, restore-intent-v1 1, hook-continue 2) and zero false
positives.

### D-P4: the doctor probe seam is a new lib, `scripts/lib/ruby_probe.rb`

The house pattern for an injectable probe is `scripts/lib/power_tools.rb` (pure detectors,
`doctor.rb` wraps them and takes them as keyword defaults: see `check_serena(cwd:, path_probe:
PowerTools.method(:which_serena))`). The new check follows that exactly:

- `RubyProbe.resolve(capture: default_capture)` returns `{found:, version:, path:}`.
- `Doctor#check_ruby_runtime(probe: RubyProbe.method(:resolve))`.

Injection is a keyword argument with a real default. No `eval`. No `ENV` seam. No global config
seam. Tests pass a lambda and never spawn a process. `doctor.rb` is already 3098 lines, so the
probe goes in `lib/` rather than growing it further, and the separate unit is what makes the AC5
mechanism test possible at all.

Cost to remember: a new file under `scripts/lib/` is NOT installed unless it is added to the
core-file map in `scripts/lib/installer_core.rb` (around line 310). ACTION_4 does that. Without
it, an installed `~/.plastic/scripts/doctor.rb` would raise `LoadError` on `require_relative
"lib/ruby_probe"` for every user. This is the single highest-risk step in the whole plan.

### D-P5: how the check resolves "which ruby would a hook get"

One spawn, and it is the same spawn a launcher makes:

```
Open3.capture3({"RUBYOPT" => nil}, "ruby", "-rrbconfig", "-e", "puts RUBY_VERSION; puts RbConfig.ruby")
```

- The command word is the bare name `ruby`, so the operating system resolves it on the inherited
  `PATH` exactly the way `execvp` does for a spawned bash launcher. We do not read `PATH`
  ourselves and we do not simulate the search.
- The resolved interpreter answers for itself: `RUBY_VERSION` is its own version and
  `RbConfig.ruby` is its own absolute path. There is no guessing and no second lookup.
- `RUBYOPT` is cleared in the probe too. This is deliberate. After this intent every launcher
  clears it, so the cleared spawn is the honest simulation of the post-fix world, and it also
  means the check cannot itself crash on the exact machine that needs the report most (Ruby 2.6
  plus a shell that exports `RUBYOPT=--yjit`).

Graceful degradation, three honest branches, never a crash:

| Situation | Result |
|---|---|
| `ruby` not on PATH (`Errno::ENOENT`), or the spawn fails, or the probe raises | `warn`: could not determine which ruby a hook would resolve |
| Output present but no parseable version | Same `warn` |
| Version below `Preflight::RUBY_FLOOR` | `warn`, naming the version, the absolute path, and the mise fix |
| Version at or above the floor | `pass`, naming the version and the path |

### D-P6: the check is named `runtime` / `ruby_floor` and is registered in `run_checks` only

- `category: "runtime"`, `name: "ruby_floor"`. It follows `codex_version_floor`'s naming style
  (a `_floor` check that compares a probed version against a constant). It does NOT go in the
  existing `tools` category, whose own comment scopes it to optional code-navigation power tools
  where absence is a pass. Ruby is not optional, so it gets its own category.
- Registered in `Doctor#run_checks` (the default full run, what `/plastic-doctor` invokes).
- NOT registered in `run_core_checks`. That scope is binary: any warn becomes a fail. A machine
  whose `PATH` ruby is old can still have a perfectly correct install, and turning that into a
  hard `--core` failure would break install verification for a risk the check can only report,
  not confirm.
- NOT registered in `run_store_checks` or `run_intent_check`. Neither is about the runtime.
- The floor constant is NOT duplicated. `doctor.rb` gains `require_relative "lib/preflight"` and
  reads `Preflight::RUBY_FLOOR` and `Preflight::RUBY_PIN`. `preflight.rb` is already in the
  installer's core-file map, so nothing else is needed.
- Below floor is `warn`, never `fail`. Report only, per spec.md D6. The executor must not
  upgrade it.

### D-P7: `hooks/savepoint`, `hooks/run-hook` and `hooks/statusline` need no changes

Checked directly, since the research table did not list `savepoint` or `statusline`:

- `hooks/savepoint` (6 lines): pure bash, one `cat <<'HOOKJSON'` heredoc printing a JSON object.
  No ruby, no spawn of any kind. No change.
- `hooks/statusline` (208 lines): pure bash by design. Its own header comment reads "Pure bash
  (macOS 3.2 compatible). No ruby, no jq." Uses only `grep`, `sed`, `awk`, `ls`, `printf` and
  shell builtins. No change.
- `hooks/run-hook` (7 lines): `exec "$HOOK_DIR/$HOOK_NAME" "$@"`. It runs a sibling hook by path
  and lets that file's shebang pick the interpreter. It never types `ruby`, so it is not a spawn
  site, matching the research note. No change.

All three are still scanned by the ACTION_6 test and pass with no exemption.

### D-P8: the research line numbers have drifted, so edits match on text

The spawn-site table in `resources/research--ruby-26-runtime-feasibility.md` is correct about
WHICH sites exist and WHAT the fix is, but several line numbers are stale against the current
files. Verified today:

| Site | Research says | Actually is |
|---|---|---|
| `hooks/check-update` | 31 | 34 |
| `hooks/continue` | 4, 19 | 3, 17 |
| `hooks/future-intent-check` | 3, 23 | 3, 25 |
| `hooks/gate-check` | 4, 10, 15 | 3, 9, 12 |

All other listed line numbers were confirmed correct (`bin/plastic.js:47`, `hooks/auto-arm:3,5`,
`hooks/bash-gate:3`, `hooks/edit-gates:3`, `hooks/power-tools:8`, `hooks/session-start:9`,
`scripts/link-suggest:198`, `scripts/maintenance-run:133,142,174,203,212`,
`scripts/restore-intent-v1:274`, `scripts/hook-continue:18,39`).

Every action file therefore gives the exact BEFORE text to match on, with the line number as a
locator only. The executor matches text, never line number.

## Notes

### The suite command

There is NO `Rakefile` in this repository, so `rake test` does not exist. The full suite command,
from AGENTS.md, is:

```
cd /Users/zlatko/apps/personal/plastic/.claude/worktrees/235--install-on-a-clean-mac
ruby -Itest -e 'Dir["test/*_test.rb"].each { |f| require File.expand_path(f) }'
```

Never run `ruby -Itest test/*_test.rb`. The shell expands the glob and Ruby runs only the first
file, giving a falsely small green run.

A single file runs with `ruby -Itest test/<name>_test.rb`.

### Off limits, zero changed lines

`scripts/lib/bridge.rb`, `scripts/lib/lock.rb`, `scripts/lib/worktree.rb`,
`scripts/hook-session-start`, `scripts/codex-hook`. If any action seems to need one of these,
stop and report it rather than editing.

`scripts/hook-session-start` is fixed transitively: clearing `RUBYOPT` at `hooks/session-start:9`
removes the variable from that ruby process's environment, so both of its backtick child spawns
inherit an already-clean environment. `scripts/codex-hook` cannot be fixed from outside itself
and is a recorded handoff to the codex-fixes roadmap.

### Tool fallback in the worktree

Concurrent sibling jobs can clobber the worktree pointer, so Edit or Write may be denied or may
write to the wrong tree. If that happens, fall back to a Bash ruby write with an absolute path
and ` # plastic-ok` appended to the command, for example:

```
ruby -e 'p="/Users/zlatko/apps/personal/plastic/.claude/worktrees/235--install-on-a-clean-mac/hooks/bash-gate"; s=File.read(p); s.sub!("exec ruby ") { "exec env -u RUBYOPT ruby " }; File.write(p, s)' # plastic-ok
```

Use `String#sub` with the BLOCK form when injecting text verbatim, so backslashes and `\1` in the
replacement are never interpreted.

### Constraints on every edit

- macOS `/bin/bash` 3.2 only: no heredoc inside `$(...)`, no bash 4 features, no `${var^^}`, no
  associative arrays. `env -u RUBYOPT` is BSD env and is verified working on this machine.
- No added line anywhere may contain an em-dash or an en-dash. `bin/plastic.js` already has
  em-dashes on lines 3 and 30 (pre-existing). Do not reflow, re-indent or otherwise re-touch
  those lines, or they become added lines carrying an em-dash.
- Tests: hermetic Minitest, constructor or keyword dependency injection, no `eval`, no `ENV`
  seam, no global config seam, no network, no live API calls.
- Commits: Conventional Commits, no AI attribution of any kind.
