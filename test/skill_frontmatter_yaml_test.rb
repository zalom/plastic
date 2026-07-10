# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "yaml"

# Guard test (intent 165): every skill's frontmatter must survive strict
# `YAML.safe_load`. A plain-scalar `description:` value that contains an
# unquoted colon followed by a space parses as an inline mapping value and
# raises `Psych::SyntaxError` (found in `skills/intent-continuing/SKILL.md`
# and `skills/install/SKILL.md`, pre-existing, flagged during intent 158's
# audit and fixed here). Each skill gets its own dynamically defined test
# method (mirroring the `SKILL_NAMES.each { define_method }` convention in
# `test/skill_command_lint_test.rb`), so one bad file's raised
# `Psych::SyntaxError` does not hide a second bad file in the same run: the
# red run names every offending skill, not just the first one found.
#
# Hermetic: reads SKILL.md files from disk only, no ambient session id, no
# network, no eval. DI-friendly: `skills_root` defaults to the repo root
# resolved relative to this test file.
class SkillFrontmatterYamlTest < Minitest::Test
  def self.skills_root
    File.expand_path("..", __dir__)
  end

  # Dynamic discovery (no hardcoded count, no hardcoded skill-name list): every
  # skills/*/SKILL.md, sorted for a stable test run order.
  def self.skill_md_paths
    Dir.glob(File.join(skills_root, "skills", "*", "SKILL.md")).sort
  end

  def test_skill_md_glob_is_not_empty
    refute_empty self.class.skill_md_paths, "expected to find at least one skills/*/SKILL.md file"
  end

  # Frontmatter extraction convention shared with `scripts/lib/intent_validator.rb`.
  def frontmatter_of(path)
    File.read(path).split("---", 3)[1]
  end

  skill_md_paths.each do |path|
    skill_name = File.basename(File.dirname(path))
    define_method("test_#{skill_name.tr('-', '_')}_frontmatter_is_yaml_safe") do
      # YAML.safe_load called directly (never through a rescuing helper), so a
      # parse failure raises and fails this file's own test method.
      fm = YAML.safe_load(frontmatter_of(path))

      assert_kind_of Hash, fm, "#{path} frontmatter did not parse to a Hash"
      assert fm["name"].is_a?(String) && !fm["name"].strip.empty?,
             "#{path} frontmatter is missing a non-empty name"
      assert fm["description"].is_a?(String) && !fm["description"].strip.empty?,
             "#{path} frontmatter is missing a non-empty description"
    end
  end
end
