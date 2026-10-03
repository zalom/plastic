# frozen_string_literal: true

require_relative "../test_helper"

# The git ruling of 2026-09-28: Plastic code runs no version control command
# and no report prints one. The Enola architecture boundary is the sole
# exception: it reads the checked-out source state and invokes the selected
# architecture tool.
class NoVersionControlTest < Plastic::TestCase
  ROOT = File.expand_path("../../scripts/lib", __dir__)
  SOURCES = [File.join(ROOT, "plastic.rb"), *Dir.glob(File.join(ROOT, "plastic", "**", "*.rb"))].freeze
  VERSION_CONTROL_BOUNDARY = %w[
    plastic/architecture/enola_snapshot.rb
    plastic/architecture/source_state.rb
  ].map { |path| File.join(ROOT, path) }.freeze
  PROCESS_BOUNDARY = %w[
    plastic/architecture/enola_provenance.rb
    plastic/architecture/source_state.rb
  ].map { |path| File.join(ROOT, path) }.freeze
  SPAWNS = /\b(?:system|spawn|exec|popen\w*|capture2e?|capture3|pipeline\w*)\b|`|%x/

  def test_the_kernel_has_sources
    assert_operator SOURCES.size, :>, 20
  end

  def test_no_source_names_a_version_control_program
    offenders = SOURCES.select { |path| File.read(path).match?(/\b(?:git|gh|npm)\b/) }

    assert_equal VERSION_CONTROL_BOUNDARY, offenders
  end

  def test_no_source_starts_a_process
    calls = SOURCES.flat_map { |path| File.readlines(path).reject { |line| line.strip.start_with?("#") }.grep(SPAWNS) }

    assert_equal PROCESS_BOUNDARY, SOURCES.select { |path| File.readlines(path).reject { |line| line.strip.start_with?("#") }.grep(SPAWNS).any? }
    assert_equal 3, calls.size
  end
end
