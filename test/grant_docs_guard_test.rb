# frozen_string_literal: true

require "minitest/autorun"

class GrantDocsGuardTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  COMMAND = "plastic intent grant"

  def read(path) = File.read(File.join(ROOT, path))

  def test_the_features_page_and_the_changelog_name_the_grant_command
    named = { "docs/usage/FEATURES.md" => read("docs/usage/FEATURES.md"), "CHANGELOG.md" => read("CHANGELOG.md") }

    assert_equal [], named.reject { |_, text| text.include?(COMMAND) }.keys
  end

  def test_the_detector_leaves_a_text_without_the_command_alone
    refute_includes "plastic intent park", COMMAND
  end
end
