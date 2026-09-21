# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

# Guard test (intent 55, extended by 144; narrowed by 372 to the doctor skill once
# install/update/uninstall/rollback became commands): a lifecycle skill's re-run
# instructions must issue a deterministic, pinned CLI invocation. Pinning `-y` plus
# an explicit `@<channel>` is a standing determinism convention: it keeps the
# invocation from ever hanging on an npx confirmation prompt or drifting onto an
# unpinned package.
#
# Hermetic: reads the doctor SKILL.md file from disk only, no ambient session id,
# no network, no eval. DI-friendly: `skills_root` defaults to the repo root
# resolved relative to this test file, but can be pointed elsewhere.
class SkillCommandLintTest < Minitest::Test
  EM_DASH = "—"
  EN_DASH = "–"

  def skills_root
    File.expand_path("..", __dir__)
  end

  # First token of a trimmed line, ignoring a trailing `# ...` comment.
  def first_token(line)
    line.split(/\s+#/, 2).first.to_s.strip.split(/\s+/).first
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
