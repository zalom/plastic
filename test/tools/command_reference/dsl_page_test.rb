# frozen_string_literal: true

require "rexml/document"
require_relative "../../command_reference_helper"

class CommandReferenceDslPageTest < Minitest::Test
  include CommandReferenceHelper

  def dsl = (@dsl ||= CommandReference::DslPage.new(CommandReferenceHelper.model, CommandReferenceHelper::ROOT))

  def test_every_example_command_is_a_table_key_with_declared_options
    refute_empty dsl.examples
    dsl.examples.each { |command| assert_empty command.split.grep(/\A--/) - declared_switches(command), command }
  end

  def test_the_words_of_every_example_command_are_a_table_key
    dsl.examples.each do |command|
      words = command.split.take_while { |word| word.match?(/\A[a-z][a-z-]*\z/) }.join(" ")

      assert Plastic::CLI::TABLE.key?(words), "#{command}: #{words.inspect}"
    end
  end

  def declared_switches(command)
    key = Plastic::CLI::TABLE.keys.select { |candidate| command.split.first(candidate.split.size) == candidate.split }.max_by(&:size)

    refute_nil key, command
    CommandReferenceHelper.pages.fetch(key).options.map { |option| option.switch.split.first }
  end

  def test_the_example_page_is_picked_by_its_words
    assert_equal "intent end", dsl.page.words
  end

  def test_every_drawing_is_well_formed
    refute_empty dsl.drawings
    dsl.drawings.each { |name, svg| assert_equal "svg", REXML::Document.new(svg).root.name, name }
  end

  def test_no_drawing_uses_a_bare_css_variable
    dsl.drawings.each { |name, svg| refute_includes svg, "var(", name }
  end
end
