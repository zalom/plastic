# frozen_string_literal: true

require_relative "../test_helper"

# The git ruling of 2026-09-28: Plastic code runs no version control command
# and no report prints one. The kernel runs one program, sqlite3.
class NoVersionControlTest < Plastic::TestCase
  ROOT = File.expand_path("../../scripts/lib", __dir__)
  SOURCES = [File.join(ROOT, "plastic.rb"), *Dir.glob(File.join(ROOT, "plastic", "**", "*.rb"))].freeze
  SPAWNS = /\b(?:system|spawn|exec|popen|capture2e?|capture3|pipeline\w*)\b|`|%x/

  def test_the_kernel_has_sources
    assert_operator SOURCES.size, :>, 20
  end

  def test_no_source_names_a_version_control_program
    offenders = SOURCES.select { |path| File.read(path).match?(/\b(?:git|gh|npm)\b/) }

    assert_empty offenders
  end

  def test_the_only_program_run_is_sqlite3
    calls = SOURCES.flat_map { |path| File.readlines(path).reject { |line| line.strip.start_with?("#") }.grep(SPAWNS) }

    assert_equal 1, calls.size
    assert_includes calls.first, 'Open3.capture3("sqlite3", '
  end
end
