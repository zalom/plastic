# frozen_string_literal: true

require_relative "../../command_reference_helper"

class CommandReferencePlacesTest < Minitest::Test
  Places = CommandReference::Places

  def test_the_places_that_print_are_the_work_and_knowledge_databases
    assert_equal %i[work knowledge], Places::WITH_PRINT
  end

  def test_the_search_index_is_a_place_and_the_references_database_is_not
    assert_equal [true, false], [Places.known?(:retrieval), Places.known?(:references)]
  end
end
