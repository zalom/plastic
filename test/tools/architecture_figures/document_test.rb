# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../support/architecture_figures_helper"
require "architecture_figures"
require "open3"

class ArchitectureFiguresDocumentTest < Minitest::Test
  include ArchitectureFiguresHelper

  NO_DRAWING = "Roadmaps, links, archive and backup"
  REMOVED = [/hook continue/, /\bFrontier\b/, /IntentProgress/, /(?<!::)\bLegacy\b(?!::)/, /does not call it yet/].freeze
  OLD_PAGE = %r{(?<![\w-])architecture\.md|docs/resources/|\.\./resources/}
  CLASS_NAME = /\A[A-Z]\w*(?:::\w+)+\z|\A[A-Z][a-z0-9]+(?:[A-Z][a-z0-9]*)+\z/
  PATH_NAME = %r{\A(?:scripts|tools|bin|docs|test)/[\w./-]+\z}

  def document = File.read(DOCUMENT)

  def figure_problems(text, existing)
    used = text.scan(%r{!\[[^\]]*\]\(figures/([\w-]+\.svg)\)}).flatten.uniq
    [existing - used, used - existing]
  end

  def sections_without_a_drawing(text)
    text.split(/^## /).drop(1).reject { |section| section.lines.drop(1).find { |line| !line.strip.empty? }.to_s.start_with?("![") }.map { |section| section.lines.first.strip }
  end

  def backticked(text) = text.scan(/`([^`\n]+)`/).flatten.uniq

  def unknown_names(text)
    backticked(text).select { |name| name.match?(CLASS_NAME) ? !class_exists?(name.delete_prefix("Plastic::")) : name.match?(PATH_NAME) && !File.exist?(File.join(ROOT, name)) }
  end

  def unknown_commands(text)
    backticked(text).filter_map { |span| span[/\Aplastic((?: [a-z][a-z-]*)+)/, 1]&.strip }.uniq.reject { |words| words == "help" || command_check(words) }
  end

  def slug(heading) = heading.strip.downcase.gsub(/[^\w\s-]/, "").tr(" ", "-")

  def broken_anchors(text, links)
    slugs = text.scan(/^#+ (.+)$/).flatten.map { |heading| slug(heading) }
    links.reject { |fragment| slugs.include?(fragment) }
  end

  def excluded?(path) = path.start_with?("docs/reviews/") || path == "CHANGELOG.md" || path.end_with?("architecture_figures/document_test.rb") || !File.file?(File.join(ROOT, path))

  def text_of(path) = File.binread(File.join(ROOT, path)).force_encoding("UTF-8")

  def tracked_texts
    out, _err, _status = Open3.capture3("git", "-C", ROOT, "ls-files")
    out.lines.map(&:strip).reject { |path| excluded?(path) }.to_h { |path| [path, text_of(path)] }.select { |_path, text| text.valid_encoding? && !text.include?("\0") }
  end

  def test_the_subjects_are_read_from_the_disk
    refute_empty document
    refute_empty tracked_texts
  end

  def test_the_document_uses_every_figure_and_only_existing_ones
    assert_equal [[], []], figure_problems(document, committed_figures.keys)
    assert_equal [["b.svg"], []], figure_problems("![x](figures/a.svg)", %w[a.svg b.svg])
    assert_equal [[], ["c.svg"]], figure_problems("![x](figures/c.svg)", [])
  end

  def test_every_section_opens_with_a_drawing
    assert_equal [NO_DRAWING], sections_without_a_drawing(document)
    assert_equal ["Two"], sections_without_a_drawing("## One\n\n![a](figures/a.svg)\n\n## Two\n\nProse first.\n")
  end

  def test_every_class_and_path_the_document_names_exists
    assert_empty unknown_names(document)
    assert_equal ["IntentProgress", "scripts/lib/plastic/gone.rb"], unknown_names("`IntentProgress` `Graph::WorkGraph` `scripts/lib/plastic/gone.rb` `scripts/lib/plastic/cli.rb` `Owner`")
  end

  def test_every_plastic_command_the_document_names_is_in_the_command_table
    assert_empty unknown_commands(document)
    assert_equal ["frobnicate"], unknown_commands("`plastic frobnicate` and `plastic intent new` and `plastic help` and `plastic node add ID`")
  end

  def test_the_document_names_no_removed_class_or_command
    REMOVED.each { |pattern| refute_match pattern, document }
    assert_match REMOVED[3], "the Legacy shim"
    refute_match REMOVED[3], "Graph::Knowledge::Legacy::Index"
  end

  def test_the_old_architecture_page_is_gone_and_nothing_names_it
    refute_path_exists File.join(ROOT, "docs", "architecture.md")
    refute_path_exists File.join(ROOT, "docs", "resources")
    assert_empty tracked_texts.select { |_path, text| text.match?(OLD_PAGE) }.keys
  end

  def test_the_old_page_detector_catches_a_link_and_a_path_and_leaves_similar_names_alone
    assert_match OLD_PAGE, "](architecture.md#the-work-graph)"
    assert_match OLD_PAGE, "`docs/architecture.md`"
    assert_match OLD_PAGE, "![x](../resources/hook-events.svg)"
  end

  def test_the_old_page_detector_leaves_similar_names_alone
    refute_match OLD_PAGE, "agent-architecture.md and contributing/ARCHITECTURE.md"
  end

  def test_every_link_into_the_document_lands_on_a_heading
    links = tracked_texts.values.flat_map { |text| text.scan(%r{ARCHITECTURE\.md#([\w-]+)}).flatten } + document.scan(/\]\(#([\w-]+)\)/).flatten

    assert_empty broken_anchors(document, links)
    assert_equal ["nowhere"], broken_anchors("## The Work Graph!\n", %w[the-work-graph nowhere])
  end
end
