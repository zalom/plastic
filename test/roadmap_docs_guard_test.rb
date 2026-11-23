# frozen_string_literal: true

require "minitest/autorun"

# The roadmap commands and the printed roadmaps/ folder are gone, so no page that tells how to use Plastic names them.
class RoadmapDocsGuardTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  PAGES = %w[PLASTIC.md README.md docs/usage docs/help docs/contributing/figures hooks].freeze
  NAMED = %r{plastic roadmap|roadmaps/|Files and roadmaps}

  def files = PAGES.flat_map { |page| Dir.glob(File.join(ROOT, page, "**", "*")) + [File.join(ROOT, page)] }.select { |path| File.file?(path) }

  def test_no_instruction_page_figure_or_hook_names_a_roadmap_command_or_print
    named = files.select { |path| File.read(path).match?(NAMED) }.map { |path| path.delete_prefix("#{ROOT}/") }

    assert_equal [], named
  end

  def test_the_guard_reads_the_pages_it_names
    assert_operator files.size, :>, 10
  end
end
