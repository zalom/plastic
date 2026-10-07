# frozen_string_literal: true

require_relative "../test_helper"

# The git ruling of 2026-09-28: Plastic code runs no version control command
# and no report prints one. The kernel starts no process at all.
class NoVersionControlTest < Plastic::TestCase
  ROOT = File.expand_path("../../scripts/lib", __dir__)
  SOURCES = [File.join(ROOT, "plastic.rb"), *Dir.glob(File.join(ROOT, "plastic", "**", "*.rb"))].freeze
  SPAWNS = /\b(?:system|spawn|exec|popen\w*|capture2e?|capture3|pipeline\w*)\b|`|%x/
  # The ruling of 2026-10-07 has `plastic auto` print the worktree command for
  # the agent to run. This one file formats that line and runs nothing.
  PRINTS_THE_WORKTREE_COMMAND = File.join(ROOT, "plastic", "workflows", "worktree.rb")

  def test_the_kernel_has_sources
    assert_operator SOURCES.size, :>, 20
  end

  def test_the_worktree_command_file_is_a_source
    assert_includes SOURCES, PRINTS_THE_WORKTREE_COMMAND
  end

  def test_no_source_names_a_version_control_program
    offenders = (SOURCES - [PRINTS_THE_WORKTREE_COMMAND]).select { |path| File.read(path).match?(/\b(?:git|gh|npm)\b/) }

    assert_empty offenders
  end

  def test_no_source_starts_a_process
    calls = SOURCES.flat_map { |path| File.readlines(path).reject { |line| line.strip.start_with?("#") }.grep(SPAWNS) }

    assert_empty calls
  end
end
