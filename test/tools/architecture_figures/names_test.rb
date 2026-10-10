# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../support/architecture_figures_helper"
require "architecture_figures"

class ArchitectureFiguresNamesTest < Minitest::Test
  include ArchitectureFiguresHelper

  ALLOWED = %w[GitHub SQLite].freeze
  CODE_TOKEN = /\b(?:[A-Z][a-z0-9]+(?:[A-Z][a-z0-9]*)+|[A-Z]\w*::\w+(?:::\w+)*)\b/

  def undeclared(texts, labels) = texts.flat_map { |style, text| (style == "m") ? [text] : text.scan(CODE_TOKEN) }.uniq - labels - ALLOWED

  def test_the_subjects_are_read_from_the_disk
    refute_empty declared_names
    refute_empty drawn_texts
  end

  def test_every_declared_name_resolves
    assert_empty missing_names(declared_names)
  end

  def test_the_resolver_catches_a_name_the_code_lacks_and_passes_a_real_one
    absent = [%w[class Frontier Frontier], ["command", "intent frobnicate", "intent frobnicate"], %w[database retrieval.db retrieval.db],
      %w[table legacy_intents_data legacy_intents_data], %w[class Hash Hash], %w[class CLI::Table CLI::Table]]
    present = [%w[class RoutineRun RoutineRun], ["class", "Graph::WorkGraph", "Graph::WorkGraph"], ["command", "intent new", "intent new"],
      ["workflow", ":code_write_intent", ":code_write_intent"], %w[table document_heads document_heads], %w[database work_graph.db work_graph.db]]

    assert_equal absent, missing_names(absent)
    assert_empty missing_names(present)
  end

  def test_every_declared_label_is_drawn_in_its_own_figure
    ArchitectureFigures::FIGURES.each do |figure|
      drawn = figure.files.values.flat_map { |svg| texts(svg) }.map(&:last)

      figure.names.each { |_type, label, _ref| assert_predicate drawn.select { |text| whole_token?(label, text) }, :any?, "#{figure}: #{label}" }
    end
  end

  def test_the_label_detector_matches_a_whole_token_only
    refute whole_token?("CLI", "CLI::TABLE")
    assert whole_token?("CLI", "the CLI reads")
  end

  def test_every_code_token_drawn_is_declared_by_its_own_figure
    ArchitectureFigures::FIGURES.each do |figure|
      drawn = figure.files.values.flat_map { |svg| texts(svg) }

      assert_empty undeclared(drawn, figure.names.map { |_type, label, _ref| label }), figure.to_s
    end
  end

  def test_the_token_detector_catches_a_stale_name_and_leaves_plain_words_alone
    assert_equal ["Workflow::Code"], undeclared([["s", "calls Workflow::Code"]], [])
    assert_empty undeclared([["s", "Owner and Agent"]], [])
  end
end
