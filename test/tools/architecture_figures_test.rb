# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../docs_stale_words_guard_test"
require_relative "../support/architecture_figures_helper"
require "architecture_figures"
require "tmpdir"

class ArchitectureFiguresTest < Minitest::Test
  include ArchitectureFiguresHelper

  def bare_variables(text) = text.scan(/var\(--[\w-]+\)/)

  def test_the_subjects_are_read_from_the_disk
    refute_empty committed_figures
    refute_empty ArchitectureFigures.render
  end

  def test_every_committed_figure_equals_a_fresh_render
    ArchitectureFigures.render.each { |name, svg| assert_equal svg, committed_figures[name], name }
  end

  def test_two_renders_are_identical
    assert_equal ArchitectureFigures.render, ArchitectureFigures.render
  end

  def test_the_figure_folder_holds_exactly_the_generated_files
    assert_equal ArchitectureFigures.render.keys.sort, committed_figures.keys.sort
    Dir.mktmpdir do |dir|
      ArchitectureFigures.build(dir)

      assert_equal ArchitectureFigures.render.keys.sort, Dir.children(dir).sort
    end
  end

  def test_no_figure_uses_a_variable_without_a_fallback
    assert_empty ArchitectureFigures.render.values.flat_map { |svg| bare_variables(svg) }
  end

  def test_the_variable_detector_catches_a_bare_variable_and_leaves_a_fallback_alone
    assert_equal ["var(--ink)"], bare_variables("fill: var(--ink)")
    assert_empty bare_variables("fill: var(--ink, #111)")
  end

  def test_every_figure_carries_its_own_light_and_dark_tokens
    ArchitectureFigures.render.each do |name, svg|
      assert_includes svg, 'class="background"', name
      assert_includes svg, "prefers-color-scheme: dark", name
    end
  end

  def test_every_figure_is_well_formed_xml
    ArchitectureFigures.render.each_value { |svg| REXML::Document.new(svg) }
  end

  def test_every_id_is_prefixed_by_its_file_and_unique_across_figures
    ids = ArchitectureFigures.render.flat_map do |name, svg|
      svg.scan(/\bid="([^"]+)"/).flatten.each { |id| assert_match(/\A#{File.basename(name, ".svg")}-/, id) }
    end

    assert_equal ids.uniq, ids
  end

  def test_every_figure_has_a_title_and_a_description
    ArchitectureFigures.render.each do |name, svg|
      document = REXML::Document.new(svg)

      %w[title desc].each { |tag| refute_empty document.get_elements("//#{tag}").first.text.to_s, "#{name} #{tag}" }
    end
  end

  def test_no_figure_names_an_intent_or_a_date
    ArchitectureFigures.render.each_value do |svg|
      refute_match DocsStaleWordsGuardTest::INTENT_ID, svg
      refute_match DocsStaleWordsGuardTest::DATE, svg
    end
  end
end
