# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../support/architecture_figures_helper"
require "architecture_figures"

class ArchitectureFiguresCommandCallTest < Plastic::TestCase
  include ArchitectureFiguresHelper

  def normalize(line) = line.gsub(/\b(intent:?|start|auto) \d+/) { |match| match.sub(/\d+/, "ID") }.gsub(/\d+--sample-title/, "ID--slug").squeeze(" ").strip

  def real_report(result) = result.out.lines.map { |line| normalize(line) }.reject(&:empty?)

  def test_the_drawn_report_lines_match_a_real_intent_new
    drawn = texts(ArchitectureFigures.render.fetch("command-call.svg")).filter_map { |style, text| normalize(text) if style == "r" }

    result = plastic("intent", "new", "Sample title", table: Plastic::CLI::TABLE)

    refute_empty drawn
    assert_equal [0, ""], [result.code, result.err]
    assert_empty drawn - real_report(result)
  end

  def test_the_normalizer_turns_ids_into_a_placeholder
    assert_equal "intent: ID", normalize("intent: 12")
    assert_equal "store/ID--slug/intent.md", normalize("        store/7--sample-title/intent.md")
    assert_equal "1 document in x.db", normalize("1  document in x.db")
  end

  def test_the_normalizer_turns_the_ids_of_the_start_commands_into_a_placeholder
    assert_equal "plastic intent start ID or plastic intent auto ID", normalize("plastic intent start 3 or plastic intent auto 3")
  end
end
