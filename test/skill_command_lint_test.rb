# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

# Guard test (intent 55): the four lifecycle skills must issue a deterministic,
# pinned CLI invocation everywhere. A bare `npx @zalom/plastic ...` (or a bare
# `@latest`) resolves the broken 0.0.1 npm stub; `-y` plus a pinned `@<channel>`
# is the fix that keeps the invocation from ever hanging on an npx confirmation
# prompt or drifting onto an unpinned package. This test makes that contract
# executable so the skills cannot silently regress.
#
# Hermetic: reads the four SKILL.md files from disk only, no ambient session
# id, no network, no eval. DI-friendly: `skills_root` defaults to the repo
# root resolved relative to this test file, but can be pointed elsewhere.
class SkillCommandLintTest < Minitest::Test
  EM_DASH = "—"
  EN_DASH = "–"

  SKILL_NAMES = %w[install update uninstall versions].freeze

  def skills_root
    File.expand_path("..", __dir__)
  end

  def skill_path(name)
    File.join(skills_root, "skills", name, "SKILL.md")
  end

  # Every ```bash fenced block's lines, in order, across the whole file.
  def bash_block_lines(content)
    content.scan(/```bash\n(.*?)```/m).flatten.flat_map(&:lines)
  end

  # First token of a trimmed line, ignoring a trailing `# ...` comment.
  def first_token(line)
    line.split(/\s+#/, 2).first.to_s.strip.split(/\s+/).first
  end

  SKILL_NAMES.each do |name|
    define_method("test_#{name}_skill_has_no_em_or_en_dash") do
      content = File.read(skill_path(name))
      refute_includes content, EM_DASH, "#{name}/SKILL.md contains an em-dash"
      refute_includes content, EN_DASH, "#{name}/SKILL.md contains an en-dash"
    end

    define_method("test_#{name}_skill_npx_and_bunx_commands_are_confirmed_and_pinned") do
      content = File.read(skill_path(name))
      command_lines = bash_block_lines(content).select { |line| %w[npx bunx].include?(first_token(line)) }
      refute_empty command_lines, "#{name}/SKILL.md has no npx/bunx command lines to check"

      command_lines.each do |line|
        command = line.split(/\s+#/, 2).first.to_s
        assert_includes command, " -y ", "#{name}/SKILL.md command missing -y: #{line.strip}"
        assert_includes command, "@zalom/plastic@",
                         "#{name}/SKILL.md command missing a pinned channel: #{line.strip}"
      end
    end
  end

  # --- doctor skill (intent 38) ---
  #
  # The doctor skill's re-run-installer command lives inline in a table cell
  # backtick span, not inside a ```bash fenced block, so it needs its own
  # extraction: every inline `...` span whose first token is npx/bunx.

  def doctor_skill_path
    File.join(skills_root, "skills", "doctor", "SKILL.md")
  end

  def inline_backtick_spans(content)
    content.scan(/`([^`]*)`/).flatten
  end

  def test_doctor_skill_has_no_em_or_en_dash
    content = File.read(doctor_skill_path)
    refute_includes content, EM_DASH, "doctor/SKILL.md contains an em-dash"
    refute_includes content, EN_DASH, "doctor/SKILL.md contains an en-dash"
  end

  def test_doctor_skill_npx_and_bunx_commands_are_confirmed_and_pinned
    content = File.read(doctor_skill_path)
    command_spans = inline_backtick_spans(content).select { |span| %w[npx bunx].include?(first_token(span)) }
    refute_empty command_spans, "doctor/SKILL.md has no npx/bunx command spans to check"

    command_spans.each do |span|
      assert_includes span, " -y ", "doctor/SKILL.md command missing -y: #{span.strip}"
      assert_includes span, "@zalom/plastic@",
                       "doctor/SKILL.md command missing a pinned channel: #{span.strip}"
    end
  end
end
