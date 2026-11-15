# frozen_string_literal: true

require_relative "../../command_reference_helper"
require_relative "../../fixtures/wordless"
require_relative "../../fixtures/worded"

class CommandReferenceWordsTest < Minitest::Test
  def test_no_words_wrap_to_one_empty_line
    assert_equal [""], CommandReference::Words.wrap(nil, 10)
  end

  def test_words_wrap_at_the_width
    assert_equal ["aa bb", "cc"], CommandReference::Words.wrap("aa bb cc", 5)
  end

  def test_a_pipe_in_a_cell_is_escaped
    assert_equal "a\\|b", CommandReference::Words.cell("a|b")
  end
end

class CommandReferenceMissingWordsTest < Minitest::Test
  include CommandReferenceHelper

  def model = (@model ||= CommandReference::Model.new(CommandReferenceHelper::ROOT, table: Fixtures::Wordless::TABLE))

  def missing(*words) = CommandReference::Words.missing(words.map { |each| model.page(each) })

  def test_one_error_names_every_missing_word_of_a_page
    lines = missing("wordless chained")

    assert(lines.any? { |line| line.include?("code_unsaid") && line.include?("summary") })
    assert(lines.any? { |line| line.include?("code_askless") && line.include?("summary") })
    assert(lines.any? { |line| line.include?("%{problem}") && line.include?("stops_when") })
  end

  def test_a_workflow_of_a_chain_with_no_summary_is_named
    assert(missing("wordless chained").any? { |line| line.start_with?("wordless chained") && line.include?("code_unsaid") && line.include?("summary") })
  end

  def test_a_workflow_that_stands_alone_needs_no_summary
    refute(missing("wordless lone").any? { |line| line.include?("summary") })
  end

  def test_an_outcome_with_no_because_is_named
    assert(missing("wordless branching").any? { |line| line.include?("code_forked") && line.include?("left") && line.include?("because") })
  end

  def test_an_outcome_with_a_because_is_not_named
    refute(missing("wordless branching").any? { |line| line.include?("right") })
  end

  def test_a_gate_whose_reason_is_only_a_placeholder_and_that_has_no_words_is_named
    assert(missing("wordless chained").any? { |line| line.include?("gate") && line.include?("%{problem}") })
  end

  def test_a_command_with_no_workflow_and_no_changes_is_named
    assert(missing("wordless bare").any? { |line| line.start_with?("wordless bare") && line.include?("changes") })
  end

  def test_a_store_the_command_writes_with_no_change_in_words_at_that_place_is_named
    assert(missing("wordless lone").any? { |line| line.start_with?("wordless lone") && line.include?("work") && line.include?("changes") })
  end

  def test_the_words_of_every_page_are_collected_in_one_list
    pages = ["wordless chained", "wordless branching"].map { |words| model.page(words) }

    assert_operator CommandReference::Words.missing(pages).size, :>, 1
    assert_equal CommandReference::Words.missing(pages), pages.flat_map { |page| CommandReference::Words.missing([page]) }
  end

  def test_the_build_fails_once_with_the_whole_list
    build = CommandReference::Build.new(CommandReferenceHelper::ROOT, table: Fixtures::Wordless::TABLE)
    error = assert_raises(CommandReference::MissingWords) { build.files }

    CommandReference::Words.missing(Fixtures::Wordless::TABLE.keys.map { |words| model.page(words) }).each { |line| assert_includes error.message, line }
  end
end

class CommandReferenceCompleteWordsTest < Minitest::Test
  include CommandReferenceHelper

  def test_a_page_with_every_word_is_named_nowhere
    model = CommandReference::Model.new(CommandReferenceHelper::ROOT, table: Fixtures::Worded::TABLE)

    assert_empty CommandReference::Words.missing(Fixtures::Worded::TABLE.keys.map { |words| model.page(words) })
  end
end

class CommandReferenceRealWordsTest < Minitest::Test
  include CommandReferenceHelper

  def missing(words) = CommandReference::Words.missing([page(words)])

  def test_intent_context_words_the_change_it_makes_in_the_knowledge_graph
    assert_empty missing("intent context")
  end

  def test_config_set_words_the_change_it_makes_in_the_settings
    assert_empty missing("config set")
  end
end

class CommandReferencePlacesTest < Minitest::Test
  def test_every_graph_a_command_can_declare_is_a_place
    assert(Plastic::CLI::Declarations::GRAPHS.all? { |graph| CommandReference::Places.known?(graph) })
  end

  def test_the_store_the_backups_the_local_database_the_home_and_the_harness_are_places
    assert(%i[store backups local home harness].all? { |place| CommandReference::Places.known?(place) })
  end

  def test_a_word_that_is_no_place_is_unknown
    refute CommandReference::Places.known?(:weather)
  end

  def test_a_change_at_an_unknown_place_is_named_by_the_check
    flow = Struct.new(:key, :klass, :rows, :outcomes).new(:only, Struct.new(:steps, :summary).new([], nil), [], [])
    page = Struct.new(:words, :flows, :klass).new("odd", [flow], Struct.new(:writes, :changes).new([], { weather: "The weather changes" }))

    assert(CommandReference::Words.missing([page]).any? { |line| line.include?("weather") && line.include?("place") })
  end
end
