# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"

require_relative "../scripts/lib/rule_catalog"
require_relative "../scripts/doctor"

# Intent 274: RuleCatalog is the one lookup surface for both axes of the rule vocabulary -
# EXCLUDABLE_CHECKS (which doctor checks a doctor-exclusions file may name) and REVISION_RULES
# (the `[rule: <tag>]` vocabulary every revisions.md entry must carry). These tests pin both
# axes against the vocabulary actually in use, so neither set can silently drift from reality.
class RuleCatalogTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)

  # A pin, not a tautology: extending EXCLUDABLE_CHECKS beyond v1's one key must be a
  # deliberate edit to this test (spec D3: signals_complete stays out).
  def test_excludable_checks_is_exactly_the_two_registered_rules
    assert_equal %w[backfilled_complete savepoint_operational], RuleCatalog::EXCLUDABLE_CHECKS.keys.sort
  end

  # Every key of EXCLUDABLE_CHECKS must be a check name doctor actually emits, so an exclusion
  # rule can never name a check that does not exist.
  def test_every_excludable_check_is_a_real_doctor_check_name
    home = Dir.mktmpdir("plastic-rule-catalog")
    File.write(File.join(home, "INDEX.md"), "# Index\n\n## Active\n\n## Future\n\n" \
                                            "## Clusters\n\n## Abandoned\n\n## Completed\n")
    emitted_names = Doctor.new(plastic_home: home).check_done_signals.map { |c| c[:name] }

    RuleCatalog::EXCLUDABLE_CHECKS.each_key do |name|
      assert_includes emitted_names, name, "EXCLUDABLE_CHECKS names #{name.inspect}, which " \
        "doctor's check_done_signals never emits"
    end
  ensure
    FileUtils.remove_entry(home) if home && Dir.exist?(home)
  end

  # Every `[rule: <literal>]` and `rule: "<literal>"` hardcoded under scripts/ must be a
  # registered REVISION_RULES member, so an unregistered tag is caught before it ships.
  # Comment-only lines are skipped: they carry template placeholders (`tag`, `<tag>`,
  # `#{rule}`) that are never real tags, not code.
  def test_every_hardcoded_rule_literal_under_scripts_is_registered
    found = []
    Dir.glob(File.join(REPO, "scripts", "**", "*")).each do |path|
      next unless File.file?(path)

      File.foreach(path) do |line|
        next if line.strip.start_with?("#")

        line.scan(/\[rule:\s*([a-z][a-z0-9-]*)\]/) { |(tag)| found << tag }
        line.scan(/rule:\s*"([a-z][a-z0-9-]*)"/) { |(tag)| found << tag }
      end
    end
    found.uniq!

    refute_empty found, "expected at least one hardcoded [rule:]/rule: literal under scripts/"
    unregistered = found.reject { |tag| RuleCatalog.revision_rule?(tag) }
    assert_empty unregistered,
      "hardcoded rule literal(s) under scripts/ missing from RuleCatalog::REVISION_RULES: " \
      "#{unregistered.join(", ")}"
  end
end
