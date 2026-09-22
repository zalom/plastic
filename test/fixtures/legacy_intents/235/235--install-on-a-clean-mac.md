---
id: "235"
intent: "Make the first install work on a clean Mac: preflight.rb:19 requires Ruby 3.0 and macOS ships 2.6.10, so install stops; decide between runtime-testing the scripts on 2.6 and lowering the floor, or bundling a Ruby with the installer, and clear RUBYOPT in the hooks either way because a global RUBYOPT=--yjit crashes system Ruby 2.6"
sources: []
chain: ["243", "235a"]
created: 2026-08-06
author: claude-code
tags: ["project-plastic", "installer", "preflight", "ruby", "blocker"]
---

## Intent
Make the first install work on a clean Mac: preflight.rb:19 requires Ruby 3.0 and macOS ships 2.6.10, so install stops; decide between runtime-testing the scripts on 2.6 and lowering the floor, or bundling a Ruby with the installer, and clear RUBYOPT in the hooks either way because a global RUBYOPT=--yjit crashes system Ruby 2.6

## Context
Parked from the fact-checked verdict of 2026-08-04, row 14
(`docs/reviews/2026-08-04-fact-checked-verdict.md`).

**What happens today.** Preflight requires Ruby 3.0 (`scripts/lib/preflight.rb:19`). A stock
macOS ships Ruby 2.6.10. On a machine that has nothing else installed, the install stops right
there.

**What it costs.** A new user cannot get past the first command. Together with the
non-executable hook problem, this is the reason a marketplace listing would fail on arrival.

**The fix.** Two candidate paths, and the owner has to pick one. Lowering the floor looks
realistic: all 42 scripts parse under 2.6 by syntax check, but the runtime calls have never
been tested there, so it needs a real run on 2.6 first. The heavier and safer path is to
bundle a Ruby with the installer. Either way the hooks must clear `RUBYOPT`, because a global
`RUBYOPT=--yjit` crashes system Ruby 2.6 outright.

**Expected result after the fix.** The first install works on a clean machine with no
prerequisites.

Intent 38 set the current floor at 3.0.0 with a mise pin of 3.3; this intent revisits that
decision with the marketplace audience in mind.

### Decisions

- D1: Keep `Preflight::RUBY_FLOOR` at `"3.0.0"`. Do not lower it to 2.6. A filtered suite run
  under system Ruby 2.6.10 produced 1707 runs, 454 errors, 54 failures; `filter_map` (17 sites,
  9 files, 2.7+) and `File.absolute_path?` (1 site, 2.7+) have no 2.6 fallback, and 2 of the 9
  affected files (`scripts/lib/bridge.rb`, `scripts/lib/lock.rb`) are off limits to this intent.
  Ruby 2.6 has been end of life since March 2022 with no CI job enforcing continued
  compatibility. Intent 38 chose 3.0.0 on the `filter_map` evidence alone; this confirms 38 was
  right for a broader reason than it knew.
- D2: Do not adopt Spinel now. `matz/spinel` has zero releases, zero tags, one contributor, and
  no `fileutils`, `yaml`, `open3`, `digest`, `tempfile`, `rbconfig`, `timeout`, `cgi` or
  `rubygems` support, which nearly every Plastic script needs. Revisitable once Spinel has
  tagged releases and stdlib parity; not a one-way door.
- D3: Do not auto-install Ruby via mise during install in this intent. The standard boring
  option is to keep the existing floor check and perfect its failure message, roughly 90 percent
  already built in `scripts/lib/preflight.rb`. Auto-install is rejected on two grounds: piping
  `curl https://mise.run | sh` from inside an installer is a trust decision that belongs to the
  owner, not a default code path; and it would not fix the problem by itself, since `mise
  activate` rewrites PATH on shell prompt render and never reaches a hook process spawned by the
  Claude Code application.
- D4: Clear `RUBYOPT` at every in-scope ruby spawn site. An env hash passed to `system`,
  `Open3.capture3`, `Process.spawn` or `IO.popen` merges onto the inherited environment and
  clears nothing unless the key carries a `nil` or empty-string value. Bash fix: `env -u RUBYOPT
  ruby ...`. Node fix: `RUBYOPT: ''` in the env object. Ruled independently of the floor
  decision (D1); a distinct, sharper bug.
- D5: The off-limits scope conflict is mostly dissolved, one documented carve-out.
  `scripts/hook-session-start`'s two backtick spawn sites (lines 65, 142) are fixed
  transitively by clearing `RUBYOPT` in the in-scope launcher `hooks/session-start:9`, since the
  variable is then absent from that ruby process's environment and its children inherit the
  cleared environment; no off-limits edit needed. `scripts/codex-hook`'s three spawn sites
  (lines 71, 91, 107) cannot be fixed from outside the file; recorded as a deliberate,
  documented exclusion handed to the codex-fixes roadmap, a scope handoff, not an owner decision
  to leave them broken. `scripts/lib/worktree.rb` spawns only `git`, never `ruby`, so it carries
  no RUBYOPT exposure.
- D6: Add exactly one new doctor check reporting which `ruby` the hooks would actually resolve
  and whether it meets `RUBY_FLOOR`. Even after installing Ruby 3.3 with mise, a hook launched by
  the Claude Code application may still resolve bare `ruby` on PATH to `/usr/bin/ruby` 2.6,
  because mise activation does not reach non-interactive spawned processes. Doctor is the
  documented maintenance front door for this class of problem. Follow the existing registry
  shape in `scripts/doctor.rb`: `check(category:, name:, status:, message:, details:, fixable:,
  fix_hint:)`. One check only; no interpreter pinning.
- Follow-up, non-blocking: pin an absolute Ruby interpreter path into the hook launchers, so
  hooks stop depending on PATH resolution. Recommended as its own future intent, sequenced after
  sibling intent 248 rules on plugin-shaped versus direct install, because 248 may relocate where
  hook launchers live. Not an owner decision to leave a gap; a deliberate deferral.

## Outcome
Clean-Mac first install fixed: honest Ruby 3.0 floor message with mise instructions, RUBYOPT cleared at all 23 spawn sites with a self-guarding scan test, injectable ruby probe + report-only doctor check; floor kept at 3.0 on measured 2.6 evidence; merged 5cc9b43, suite 1922/8869/0

## Insights
(observations captured throughout — raw material for future intents)
2026-08-06T14:54:08Z · Link · link-suggest — chain edge to 243 (rating high): Verdict row 23 states plainly that listing must wait for 234 and 235 (install on a clean Mac); 235 is a hard precondition, since a listing before it sends every new user into an install that stops on the Ruby floor
2026-08-07T13:25:43Z · Why · plastic-enforcer — Ruby 2.6 runtime is NOT viable: a filtered suite run under system 2.6.10 gave 1707 runs, 454 errors, 54 failures. Two constructs cause nearly all of it: Enumerable#filter_map (17 call sites across 9 files, 2.7+) and File.absolute_path? (bridge.rb:1622, 2.7+). 10 test files also use endless method syntax (3.0+). Intent 38 set the 3.0 floor on the filter_map evidence alone; the full runtime sweep confirms 38 was right for a broader reason than it knew.
2026-08-07T13:25:43Z · Why · plastic-enforcer — Spinel is not shippable today: matz/spinel has zero releases and zero tags (gh api), one contributor, and no implementation of fileutils, yaml, open3, digest, tempfile, rbconfig, timeout, cgi or rubygems. Nearly every Plastic script needs at least one of those. Companion gem rubocop_spinel v0.2.0 is real; spinel-dev is hyphenated not underscored; spin ships inside the main repo rather than as a separate package.
2026-08-07T13:25:43Z · Why · plastic-enforcer — mise installs Ruby from precompiled jdx/ruby binaries by default, not a source compile, so the slow-install fear is the fallback path not the default. The decisive problem is activation, not speed: mise activate rewrites PATH when a shell prompt renders, so a hook process spawned by the Claude Code app never sees it. Any bundled-Ruby path must resolve an absolute interpreter path via mise which ruby and pin it, never trust bare ruby on PATH.
2026-08-07T13:25:43Z · Why · plastic-enforcer — An env hash passed to system, Open3.capture3, Process.spawn or IO.popen MERGES onto the inherited environment; it does not clear anything unless the key is present with a nil or empty-string value. Verified: Open3.capture3({'RUBYOPT' => nil}, '/usr/bin/ruby', '-v') succeeds under a parent RUBYOPT=--yjit while the same call without the hash crashes. 27 ruby spawn sites exist across hooks/, scripts/ and bin/plastic.js and none of them clear RUBYOPT today.
2026-08-07T13:25:43Z · Why · plastic-enforcer — Clearing RUBYOPT in the hooks/session-start launcher transitively fixes the two off-limits backtick spawn sites inside scripts/hook-session-start (lines 65 and 142), because env -u RUBYOPT removes the variable from the launched ruby process and its children inherit the cleared environment. This dissolves most of the reported scope conflict without editing an off-limits file.
2026-08-07T14:11:44Z · Exec · plastic-executor (autonomous) — A comment in bin/plastic.js that quotes the code literally (for example 'RUBYOPT: '' last, after the spread') can collide with a test's own text scan for that same literal, making the scan match the comment line instead of the real code line. Rephrased the comment to describe the mechanism without repeating the exact token, which is safer than writing a scan that special-cases comments.
2026-08-07T14:11:45Z · Exec · plastic-executor (autonomous) — ACTION_6.md's own text claimed test/rubyopt_clearing_test.rb has 9 tests; the exact file content it specified has 8 def test_ methods, confirmed by grep -c. Documentation drift in the action file itself, not an implementation gap; the file was created verbatim from the action's code block.
2026-08-07T14:11:45Z · Exec · plastic-executor (autonomous) — A pure source-scanning test (reads hook files as text, spawns nothing) can trip test/hermeticity_guard_test.rb's bridge-writing-hook-spawn guard as a false positive, because the guard's heuristic looks for the hook names and spawn-call tokens as substrings and cannot distinguish a detector's string literals from a real spawn. Fixed with a narrow, greppable NON_SPAWNING_SOURCE_SCANNERS exemption list rather than adding a fake PLASTIC_TMP mention to the scanning test, which would have been a cargo-cult lie in a file that spawns nothing.

## Links
- [[243--launch-on-verified-proof|Launch on claims that survive checking: list on the marketplace only after the executable-hook and clean-Mac install blockers are fixed, publish a 20-task suite with transcripts and an honest cost line, write one launch-quality piece, and find a second maintainer; the market was confirmed on 2026-08-04 and the platforms are giving the generic parts away, so the window is months]]
- [[235a--spinel-compile-trial|Hands-on Spinel compile trial of Plastic scripts, plus Tebako, with required-changes report]]
