# frozen_string_literal: true

require_relative "test_helper"

# Plastic code names no program it does not depend on, such as gh or npm. Git is a
# hard dependency, since the stores are versioned in it, so instruction text may
# name it as the example of version control. The kernel starts no process at all;
# KernelStartsNoProcessGuardTest parses the source and so tells a command from a
# backtick inside instruction text.
class NoVersionControlGuardTest < Minitest::Test
  ROOT = File.expand_path("../lib", __dir__)
  SOURCES = [File.join(ROOT, "plastic.rb"), *Dir.glob(File.join(ROOT, "plastic", "**", "*.rb"))].freeze
  PROGRAM = /\b(?:gh|npm)\b/

  def test_the_kernel_has_sources
    assert_operator SOURCES.size, :>, 20
  end

  def test_the_detector_finds_a_program_name_in_a_line
    assert_match PROGRAM, "gh pr create"
    assert_match PROGRAM, "npm install"
  end

  def test_the_detector_leaves_git_which_plastic_depends_on
    refute_match PROGRAM, "Use version control, such as Git, as the project's AGENTS.md defines it"
  end

  def test_the_detector_leaves_a_word_that_holds_a_program_name
    refute_match PROGRAM, "digit github legit"
  end

  def test_no_source_names_a_program_plastic_does_not_depend_on
    offenders = SOURCES.select { |path| File.read(path).match?(PROGRAM) }

    assert_empty offenders
  end
end
