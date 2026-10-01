# frozen_string_literal: true

require_relative "../test_helper"

# The git ruling of 2026-09-28: Plastic code runs no version control command
# and no report prints one. The kernel runs no program: SQLite comes through the sqlite3 gem.
class NoVersionControlTest < Plastic::TestCase
  ROOT = File.expand_path("../../scripts/lib", __dir__)
  SOURCES = [File.join(ROOT, "plastic.rb"), *Dir.glob(File.join(ROOT, "plastic", "**", "*.rb"))].freeze
  SPAWNS = /\b(?:system|spawn|exec|popen\w*|capture2e?|capture3|pipeline\w*)\b|`|%x/

  def test_the_kernel_has_sources
    assert_operator SOURCES.size, :>, 20
  end

  def test_no_source_names_a_version_control_program
    offenders = SOURCES.select { |path| File.read(path).match?(/\b(?:git|gh|npm)\b/) }

    assert_empty offenders
  end

  def test_the_kernel_runs_no_program
    calls = SOURCES.flat_map { |path| File.readlines(path).reject { |line| line.strip.start_with?("#") }.grep(SPAWNS) }

    assert_empty calls
  end
end
