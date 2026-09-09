# ACTION_6: the RUBYOPT clearing regression test

Intent: 235, Make the first install work on a clean Mac.
Satisfies: AC4, AC12.
Depends on: ACTION_1, ACTION_2 and ACTION_3 must all be done first. Written before them, this
test is red for the whole delivery.

## Context you need (do not go looking for it)

AC4 requires a test that reads each in-scope spawn site's source and asserts the clearing pattern
is present. The valuable property, and the reason this is a test and not a one-time grep, is that
it must also catch a NEW hook added later that spawns ruby without clearing.

The design (recorded in plan.md as D-P1, D-P2, D-P3) is neutralize-then-scan. The test does not
try to recognize a spawn site with a clever regex. It does the reverse:

1. Take a source line. Skip comments and lines carrying the exemption marker.
2. Replace every occurrence of the CLEARED form with a placeholder word.
3. Assert that no spawn token survives.

The `hooks/` half ENUMERATES the directory, so a new hook is covered with no maintenance. The
`scripts/` half NAMES four files, because `scripts/` holds many files that spawn `git` and `npm`,
and two off-limits files that legitimately still carry uncleared ruby spawns.

## Where you work

Worktree root:
`/Users/zlatko/apps/personal/plastic/.claude/worktrees/235--install-on-a-clean-mac`

New file:
`/Users/zlatko/apps/personal/plastic/.claude/worktrees/235--install-on-a-clean-mac/test/rubyopt_clearing_test.rb`

If Edit or Write is denied or writes to the wrong tree, fall back to a Bash ruby write with the
absolute path and ` # plastic-ok` appended.

## The file to create

```ruby
# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

# Every place Plastic spawns a ruby child process must clear RUBYOPT first (intent 235, AC4).
# A shell that exports RUBYOPT=--yjit otherwise hands --yjit to a child ruby, and an old
# interpreter dies on the unknown flag before it can print anything, which is how a clean Mac
# ended up being told "Ruby not found" when Ruby was right there.
#
# HOW THIS TEST DECIDES WHAT A SPAWN SITE IS
#
# It does not try to recognize a spawn with a clever pattern. It neutralizes the CLEARED form
# first, then asserts that no spawn token is left standing. Deliberately over-matching is safe,
# because every cleared spawn is neutralized before the scan runs.
#
#   shell:  cleared form is the literal "env -u RUBYOPT ruby "
#           spawn token is the bare lowercase word `ruby` followed by whitespace, not preceded
#           by a word character, a dot, a slash or a hyphen. So RUBYOPT never matches (wrong
#           case), -rjson never matches, and a path ending in hook-continue never matches.
#
#   ruby:   a line spawns ruby when it carries system( / Open3.capture3( / IO.popen( /
#           Process.spawn( AND references an interpreter (RbConfig.ruby or the literal "ruby");
#           or when it holds a BALANCED backtick pair whose command starts with ruby, after an
#           optional env -u RUBYOPT. A system(...) call that spawns git is not a ruby spawn and
#           is not flagged.
#           cleared form is a leading env hash carrying "RUBYOPT" =>, or env -u RUBYOPT ruby
#           inside a backtick command.
#
#           The balanced-pair requirement is load bearing, not decoration. restore-intent-v1
#           has a user-facing warning string holding a single unmatched backtick followed by
#           the word ruby, closed two lines later. A naive backtick rule flags that prose as an
#           uncleared spawn. A real backtick command literal in these files is always balanced
#           on its own line, so requiring an even count of at least two drops the prose and
#           keeps every real site.
#
# KNOWN LIMIT, on purpose: the rule targets the bare-name form (`ruby ...`), which is every
# spawn site Plastic has today. An absolute-path launcher (`/opt/ruby/bin/ruby ...`) would not
# match. That form arrives only with the deferred interpreter-pinning follow-up named in intent
# 235's spec, and that intent must widen this rule.
#
# THE hooks/ SCAN ENUMERATES, IT DOES NOT USE A LIST. The only exclusion is "not a .json file",
# because hooks.json is a registry, not a script. Three other files need no exclusion at all and
# are scanned like the rest: run-hook execs a sibling hook by path and never types ruby;
# savepoint prints one JSON heredoc; statusline is pure bash by design. All three pass because
# they contain no ruby token. A NEW hook that spawns ruby without clearing fails this test
# automatically, with no maintenance.
#
# HOW TO ADD A LEGITIMATE EXCEPTION: put the marker below on the offending line with a written
# reason, for example:
#     ruby -e 'puts 1'   # plastic-rubyopt-exempt: writes its own RUBYOPT deliberately
# It is per line, it forces a reason, and it is greppable. It is unused today.
#
# KNOWN, DELIBERATE GAPS (recorded, not asserted, so this test does not fail the day they are
# closed). Both files are off limits to intent 235 and both still carry uncleared ruby spawns:
#   scripts/codex-hook:71, 91, 107   handed to the codex-fixes roadmap (spec.md, D5)
#   scripts/hook-session-start:65, 142  fixed TRANSITIVELY: hooks/session-start clears RUBYOPT
#                                       before launching it, so both backtick children inherit
#                                       an already-clean environment. No edit inside the file.
class RubyoptClearingTest < Minitest::Test
  REPO = File.expand_path("../../", __FILE__)

  EXEMPT_MARKER = "plastic-rubyopt-exempt"

  SHELL_CLEARED = "env -u RUBYOPT ruby "
  SHELL_PLACEHOLDER = "PLASTIC_CLEARED_RUBY "
  SHELL_SPAWN_TOKEN = /(?<![\w.\/-])ruby(?=\s)/

  RUBY_SPAWN_CALLS = ["system(", "Open3.capture3(", "IO.popen(", "Process.spawn("].freeze
  BACKTICK_RUBY = /`\s*(env -u RUBYOPT\s+)?ruby\s/

  # Named, not enumerated: scripts/ holds many git and npm spawns plus two off-limits files.
  RUBY_SPAWNERS = %w[
    scripts/link-suggest
    scripts/maintenance-run
    scripts/restore-intent-v1
    scripts/hook-continue
  ].freeze

  # Rename guard only. The hooks scan below enumerates the directory, it does not read this.
  KNOWN_SHELL_LAUNCHERS = %w[
    hooks/auto-arm
    hooks/bash-gate
    hooks/check-update
    hooks/continue
    hooks/edit-gates
    hooks/future-intent-check
    hooks/gate-check
    hooks/power-tools
    hooks/session-start
  ].freeze

  def shell_files
    Dir.children(File.join(REPO, "hooks")).sort
       .map { |name| File.join("hooks", name) }
       .select { |rel| File.file?(File.join(REPO, rel)) }
       .reject { |rel| rel.end_with?(".json") }
  end

  def scannable_lines(rel)
    File.readlines(File.join(REPO, rel)).each_with_index.reject do |line, _i|
      line.strip.start_with?("#") || line.include?(EXEMPT_MARKER)
    end
  end

  def uncleared_shell_spawns(rel)
    scannable_lines(rel).filter_map do |line, i|
      neutral = line.gsub(SHELL_CLEARED, SHELL_PLACEHOLDER)
      "#{rel}:#{i + 1}: #{line.strip}" if neutral =~ SHELL_SPAWN_TOKEN
    end
  end

  # A real backtick command literal is balanced on its own line. A lone backtick is prose
  # inside a message string, so it is not a spawn site.
  def ruby_spawn_line?(line)
    call_spawn = RUBY_SPAWN_CALLS.any? { |token| line.include?(token) } &&
                 (line.include?("RbConfig.ruby") || line.include?('"ruby"'))
    return true if call_spawn

    ticks = line.count("`")
    ticks >= 2 && ticks.even? && !(line =~ BACKTICK_RUBY).nil?
  end

  def uncleared_ruby_spawns(rel)
    scannable_lines(rel).filter_map do |line, i|
      next unless ruby_spawn_line?(line)

      cleared = line.include?('"RUBYOPT" =>') || line.include?(SHELL_CLEARED.strip)
      "#{rel}:#{i + 1}: #{line.strip}" unless cleared
    end
  end

  # --- shell launchers ---

  def test_every_shell_hook_clears_rubyopt_before_spawning_ruby
    offenders = shell_files.flat_map { |rel| uncleared_shell_spawns(rel) }

    assert_empty offenders,
      "these hook lines spawn ruby without clearing RUBYOPT. Put `env -u RUBYOPT` in front of " \
      "ruby, or mark the line with `# #{EXEMPT_MARKER}: <reason>` if it is genuinely fine:\n" +
      offenders.join("\n")
  end

  def test_the_hooks_scan_actually_covers_the_known_launchers
    scanned = shell_files

    KNOWN_SHELL_LAUNCHERS.each do |rel|
      assert_includes scanned, rel, "#{rel} is missing or was renamed, so it is no longer scanned"
    end
  end

  def test_the_hooks_scan_enumerates_rather_than_reading_a_list
    # If a new hook lands, it must be scanned without anyone editing this test.
    assert_operator shell_files.size, :>=, KNOWN_SHELL_LAUNCHERS.size
  end

  # --- ruby-side spawners ---

  def test_every_named_ruby_spawner_clears_rubyopt
    offenders = RUBY_SPAWNERS.flat_map { |rel| uncleared_ruby_spawns(rel) }

    assert_empty offenders,
      "these lines spawn a ruby child without clearing RUBYOPT. Add {\"RUBYOPT\" => nil} as the " \
      "leading env hash, or `env -u RUBYOPT ruby` inside a backtick command:\n" + offenders.join("\n")
  end

  def test_the_named_ruby_spawners_all_exist
    RUBY_SPAWNERS.each do |rel|
      assert File.file?(File.join(REPO, rel)), "#{rel} is missing or was renamed"
    end
  end

  # Guard against a vacuous pass: if the detector stopped recognizing spawn sites, every file
  # would look clean. Each named file must still contain at least one recognized, cleared spawn.
  def test_the_detector_still_recognizes_the_spawn_sites_it_is_meant_to_cover
    expected = {
      "scripts/link-suggest" => 1,
      "scripts/maintenance-run" => 5,
      "scripts/restore-intent-v1" => 1,
      "scripts/hook-continue" => 2,
    }

    expected.each do |rel, count|
      found = scannable_lines(rel).count { |line, _i| ruby_spawn_line?(line) }
      assert_equal count, found, "#{rel} should hold #{count} recognized ruby spawn site(s)"
    end
  end

  # --- the node entry point ---

  def test_bin_plastic_js_clears_rubyopt_in_its_child_env
    source = File.read(File.join(REPO, "bin/plastic.js"))

    assert_includes source, "RUBYOPT: ''",
      "bin/plastic.js must pass RUBYOPT: '' in the env object it hands to execFileSync"
    env_line = source.lines.find { |l| l.include?("RUBYOPT: ''") }
    assert_operator env_line.index("...process.env"), :<, env_line.index("RUBYOPT: ''"),
      "RUBYOPT: '' must come after the ...process.env spread, or the spread overwrites it"
  end

  def test_bin_plastic_js_no_longer_claims_ruby_was_not_found_when_it_was
    source = File.read(File.join(REPO, "bin/plastic.js"))

    refute_includes source, "found not found",
      "with RUBYOPT cleared, a too-old ruby runs and prints preflight's real message, so this " \
      "hardcoded fallback text is both false and unreachable"
  end
end
```

## Note on `filter_map`

The test uses `Enumerable#filter_map`, which needs Ruby 2.7 or newer. That is fine and
deliberate: `RUBY_FLOOR` is 3.0.0 and the codebase already uses `filter_map` at 17 sites. Do not
rewrite it to be 2.6 compatible.

## Hard rules

- No `eval`, no `ENV` seam, no network, no process spawn. This test only reads files.
- No added line may contain an em-dash or an en-dash.
- Do not weaken an assertion to make it pass. If a scan finds an offender, fix the source file
  (that is ACTION_1, ACTION_2 or ACTION_3), not the test.

## Verify

1. Green after ACTION_1 to ACTION_3:

```
cd /Users/zlatko/apps/personal/plastic/.claude/worktrees/235--install-on-a-clean-mac
ruby -Itest test/rubyopt_clearing_test.rb
```

Nine tests, zero failures, zero errors.

2. Prove it actually bites. Temporarily break one site, confirm the test goes red, then restore:

```
cp hooks/bash-gate /tmp/bash-gate.bak
ruby -e 'p="hooks/bash-gate"; s=File.read(p); s.sub!("exec env -u RUBYOPT ruby ") { "exec ruby " }; File.write(p, s)'
ruby -Itest test/rubyopt_clearing_test.rb ; echo "exit=$?"
cp /tmp/bash-gate.bak hooks/bash-gate && rm /tmp/bash-gate.bak
ruby -Itest test/rubyopt_clearing_test.rb
```

The middle run must FAIL and name `hooks/bash-gate:3`. The last run must pass. Confirm
`git status` is clean for `hooks/bash-gate` afterwards.

3. Prove the future-hook property. Add a throwaway hook, confirm the test catches it, remove it:

```
printf '#!/bin/bash\nruby -e "puts 1"\n' > hooks/zz-temp-probe
ruby -Itest test/rubyopt_clearing_test.rb ; echo "exit=$?"
rm hooks/zz-temp-probe
ruby -Itest test/rubyopt_clearing_test.rb
```

The middle run must FAIL and name `hooks/zz-temp-probe:2`. The last run must pass. Confirm
`git status` shows no leftover file.

4. Full suite:

```
ruby -Itest -e 'Dir["test/*_test.rb"].each { |f| require File.expand_path(f) }'
```

There is no `Rakefile` in this repo, so `rake test` does not exist.

## Done when

`test/rubyopt_clearing_test.rb` is green, both negative controls in steps 2 and 3 went red as
expected and were fully reverted, and the full suite is green.
