# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

# Hermetic structural test asserting PLASTIC.md says git is a hard dependency.
# Whitespace is normalized before matching so a test does not depend on exactly
# where a line is wrapped.
class PlasticMdPointerTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  PLASTIC_MD = File.join(ROOT, "PLASTIC.md")

  def normalized_body
    File.read(PLASTIC_MD).gsub(/\s+/, " ")
  end

  def test_plastic_md_says_git_is_a_hard_dependency
    assert_includes normalized_body, "git is a hard dependency"
  end
end

# PLASTIC.md tells the agent to load the named projects when a person asks for them.
class PlasticMdProjectLoadTest < Minitest::Test
  def normalized_body = File.read(PlasticMdPointerTest::PLASTIC_MD).gsub(/\s+/, " ")

  def test_plastic_md_names_project_load_for_the_load_projects_phrase
    assert_includes normalized_body, %("Load projects X, Y, Z", run `plastic project load`)
  end
end
