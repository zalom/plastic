# frozen_string_literal: true

require "minitest/autorun"

# The README, the install page and the usage docs serve the stable release. Beta and alpha live in
# the release lines page and the contributor docs.
class StableDocsGuardTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  STABLE_PAGES = ["README.md", "INSTALL.md", "docs/index.md", *Dir["docs/usage/**/*.md", base: ROOT]].freeze
  PRE_RELEASE = /\bbeta\b|\balpha\b|--channel/i

  def read(path) = File.read(File.join(ROOT, path))

  def test_no_stable_page_names_beta_alpha_or_a_channel_option
    named = STABLE_PAGES.select { |path| read(path).match?(PRE_RELEASE) }

    assert_equal [], named
  end

  def test_the_short_start_opens_with_project_new_after_the_install
    start = read("README.md")[/^## Quick start\n(.*?)(?=^## )/m, 1].to_s
    commands = start.lines.map(&:strip).grep(/\Aplastic /)

    assert_equal "plastic init", commands.first.split("#").first.strip
    assert_match(/\Aplastic project new /, commands[1])
  end

  def test_the_release_lines_page_holds_the_channel_commands
    assert_includes read("docs/release-lines.md"), "plastic update --channel beta"
    assert_includes read("docs/release-lines.md"), "plastic update --channel alpha"
  end

  def test_the_contributor_docs_link_to_the_release_lines_page
    assert_includes read("docs/contributing/CODING_PRACTICES.md"), "release-lines.md"
  end

  def test_the_spec_guide_names_the_four_sections_of_spec_md
    guide = read("docs/grilling.md")

    assert_equal [], ["## Goal", "## Done criteria", "## Open decisions", "## Constraints"].reject { |heading| guide.include?(heading) }
  end

  def test_the_readme_holds_no_example_output_and_no_command_list
    readme = read("README.md")

    refute_match(/^## (Examples|Commands|Global options)$/, readme)
  end

  def test_the_readme_names_no_hook_that_checks_for_a_release
    refute_match(/newer release/, read("README.md"))
  end
end
