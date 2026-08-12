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
# they contain no ruby token. Every enumerated hook is checked by BOTH detectors, the bash
# SHELL_SPAWN_TOKEN scan and the Ruby-language ruby_spawn_line? scan, so a NEW hook that spawns
# ruby without clearing fails this test automatically, with no maintenance, regardless of which
# language it spawns ruby from.
#
# HOW TO ADD A LEGITIMATE EXCEPTION: put the marker below on the offending line with a written
# reason, for example:
#     ruby -e 'puts 1'   # plastic-rubyopt-exempt: writes its own RUBYOPT deliberately
# It is per line, it forces a reason, and it is greppable. It is unused today.
#
# KNOWN, DELIBERATE GAP (recorded, not asserted, so this test does not fail the day it is
# closed). scripts/codex-hook was listed here by intent 235 and is NO LONGER a gap: intent 249
# cleared all three of its spawn sites and added it to RUBY_SPAWNERS below, so it is now
# asserted rather than recorded. One file is still off limits and still carries uncleared spawns:
#   scripts/hook-session-start:65, 142  fixed TRANSITIVELY: hooks/session-start clears RUBYOPT
#                                       before launching it, so both backtick children inherit
#                                       an already-clean environment. No edit inside the file.
class RubyoptClearingTest < Minitest::Test
  REPO = File.expand_path("../../", __FILE__)

  EXEMPT_MARKER = "plastic-rubyopt-exempt"
  # Forces an actual reason: a bare marker with no colon and text after it does not exempt
  # the line, matching the header's claim above that the marker "forces a reason".
  EXEMPT_PATTERN = /#{Regexp.escape(EXEMPT_MARKER)}:\s*\S/

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
    scripts/lib/verify_intent.rb
    scripts/codex-hook
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
      line.strip.start_with?("#") || line.match?(EXEMPT_PATTERN)
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
    # Checked by BOTH detectors regardless of language: the bash SHELL_SPAWN_TOKEN scan and
    # the Ruby-language ruby_spawn_line? scan (for example a hook written with
    # Open3.capture3("ruby", ...) or IO.popen(["ruby", ...])), because hooks/ is not
    # restricted to bash and a Ruby-language hook must not slip past either half.
    offenders = shell_files.flat_map { |rel| uncleared_shell_spawns(rel) + uncleared_ruby_spawns(rel) }

    assert_empty offenders,
      "these hook lines spawn ruby without clearing RUBYOPT. Put `env -u RUBYOPT` in front of " \
      "ruby (or a leading {\"RUBYOPT\" => nil} env hash for a Ruby-language spawn), or mark " \
      "the line with `# #{EXEMPT_MARKER}: <reason>` if it is genuinely fine:\n" +
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

  # Guard against a vacuous pass on the SHELL half: if SHELL_SPAWN_TOKEN ever stopped
  # matching a bare `ruby` command word, every hook would look clean by default and the
  # test above would give no signal at all. Counts RAW (pre-neutralization) recognized
  # command words across hooks/ only, the 14 already-cleared shell spawn sites from intent
  # 235's ACTION_2. This number covers hooks/ alone, re-derived here rather than trusted from
  # elsewhere; it does not include the named ruby-side scripts/ spawners guarded below.
  def test_the_shell_detector_still_recognizes_the_spawn_sites_it_is_meant_to_cover
    recognized = shell_files.sum { |rel| scannable_lines(rel).count { |line, _i| line =~ SHELL_SPAWN_TOKEN } }

    assert_equal 14, recognized,
      "the shell scan should recognize 14 ruby command words across hooks/, all already " \
      "cleared; if this number drops, SHELL_SPAWN_TOKEN stopped matching and the hooks test " \
      "above is vacuous"
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
      # 2, not 3: the third spawn site (the live-state branch) execs a BASH launcher, so its
      # line names neither RbConfig.ruby nor "ruby" and ruby_spawn_line? does not see it. It is
      # cleared anyway (intent 249), it just is not counted here.
      "scripts/codex-hook" => 2,
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
