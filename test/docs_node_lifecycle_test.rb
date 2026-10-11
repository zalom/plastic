# frozen_string_literal: true

require "minitest/autorun"

class DocsNodeLifecycleTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  PAGE = File.join(ROOT, "docs", "concepts", "node-lifecycle.md")
  INDEX = File.join(ROOT, "docs", "concepts", "index.md")
  STATES = %w[open claimed done failed needs_info impeded removed].freeze
  FIGURE = %r{\A!\[[^\]]+\]\(\.\./contributing/figures/node-lifecycle\.svg\)}

  def body = File.read(PAGE).gsub(/\s+/, " ")

  def opens_with_a_figure?(text) = text.lines.drop(1).map(&:strip).reject(&:empty?).first.to_s.match?(FIGURE)

  def test_the_page_is_read_from_the_disk
    assert_path_exists PAGE
  end

  def test_the_page_opens_with_the_node_lifecycle_figure
    assert opens_with_a_figure?(File.read(PAGE))
  end

  def test_the_figure_detector_catches_prose_first_and_passes_a_figure_first
    refute opens_with_a_figure?("# Title\n\nProse first.\n")
    assert opens_with_a_figure?("# Title\n\n![States](../contributing/figures/node-lifecycle.svg)\n")
  end

  def test_the_page_names_each_node_state
    assert_empty(STATES.reject { |state| body.include?("`#{state}`") })
  end

  def test_the_page_names_each_move_command
    %w[add claim done fail ask impede resolve release remove].each { |move| assert_includes body, "plastic node #{move}" }
  end

  def test_the_page_states_how_a_claim_keeps_the_lock_live
    ["1800 seconds", "7200 seconds", "plastic intent lock status"].each { |term| assert_includes body, term }
  end

  def test_the_concepts_index_links_the_page
    assert_includes File.read(INDEX), "(node-lifecycle.md)"
  end
end
