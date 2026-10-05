# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../scripts/lib/plastic/graph/knowledge/archive/writer"

class KnowledgeArchivePrintedCleanupTest < Plastic::TestCase
  def setup
    super
    open_intent
    open_intent("Beta")
  end

  def cleanup = Plastic::Graph::Knowledge::Archive::PrintedCleanup.new(store_graphs.databases, retrieval)

  def test_the_printed_records_under_the_folder_are_removed
    cleanup.remove("store/1--alpha")

    assert_empty(retrieval.printed.keys.grep(%r{\Astore/1--alpha/}))
  end

  def test_the_printed_records_of_other_folders_stay
    cleanup.remove("store/1--alpha")

    refute_empty(retrieval.printed.keys.grep(%r{\Astore/2--beta/}))
  end

  def test_a_folder_prefix_does_not_match_a_longer_name
    cleanup.remove("store/1--alph")

    refute_empty(retrieval.printed.keys.grep(%r{\Astore/1--alpha/}))
  end
end
