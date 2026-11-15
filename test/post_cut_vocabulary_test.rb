# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

# The shipped template speaks the runner vocabulary: the direct, thinking and auto modes and plastic next.
class PostCutVocabularyTest < Minitest::Test
  REPO = File.expand_path("../../", __FILE__)

  def read(rel) = File.read(File.join(REPO, rel))

  def test_the_codex_template_names_the_three_modes
    body = codex_template

    %w[direct thinking auto].each { |mode| assert_match(/\b#{mode}\b/i, body) }
  end

  def test_the_codex_template_points_at_the_delivery_loop
    assert_match(/`plastic next`/, codex_template)
  end

  private

  def codex_template
    read("lib/plastic/installations/codex_instructions.rb")[/BODY = <<~MD\n(.*?)\n\s*MD\n/m, 1].to_s
  end
end
