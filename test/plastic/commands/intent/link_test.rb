# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/intent/link"

class IntentLinkCaseTest < Plastic::TestCase
  def test_linking_two_intents_prints_the_link_and_offers_sync_down
    ran("intent new Alpha", "intent new Beta")

    assert_case line("intent link 1 cites 2"), code: 0, out: ["link: 1 cites 2", "next: plastic sync down"]
  end

  def test_linking_to_a_missing_intent_exits_1_and_names_it
    ran("intent new Alpha")

    assert_case line("intent link 1 chain 9"), code: 1, out: "", err: ["no intent 9 in this store"]
  end

  def test_linking_with_an_unknown_kind_exits_2_and_names_the_kinds
    ran("intent new Alpha", "intent new Beta")

    assert_case line("intent link 1 likes 2"), code: 2, out: "",
      err: ["KIND takes cites, supersedes, answers, source, chain"]
  end
end

class IntentLinkTest < Plastic::TestCase
  def call(*args) = plastic("intent", "link", *args, table: Plastic::CLI::TABLE)

  def test_each_kind_writes_one_row_that_reads_back_with_its_kind
    open_intent
    open_intent("Beta")

    %w[cites supersedes answers source chain].each do |kind|
      result = call("1", kind, "2")

      assert_equal 0, result.code
      links = store_graphs.retrieval.links("1").select { |link| link.kind == kind }

      assert_equal 1, links.size
      assert_equal "2", links.first.to_ref
    end
  end

  def test_an_unknown_kind_is_rejected_with_no_row_written
    open_intent
    open_intent("Beta")

    result = call("1", "nonsense", "2")

    assert_equal 2, result.code
    assert_empty store_graphs.retrieval.links("1")
  end

  def test_a_missing_target_intent_fails_with_no_row_written
    open_intent

    result = call("1", "cites", "9")

    assert_equal 1, result.code
    assert_empty store_graphs.retrieval.links("1")
  end

  def test_a_missing_target_ruling_fails_with_no_row_written
    open_intent

    result = call("1", "cites", "1/D9")

    assert_equal 1, result.code
    assert_empty store_graphs.retrieval.links("1")
  end

  def test_linking_twice_refuses_the_second_call_with_one_row_left
    open_intent
    open_intent("Beta")
    call("1", "cites", "2")

    result = call("1", "cites", "2")

    assert_equal 3, result.code
    assert_equal 1, store_graphs.retrieval.links("1").size
  end

  def test_linking_an_intent_to_itself_is_refused
    open_intent

    result = call("1", "cites", "1")

    assert_equal 3, result.code
    assert_empty store_graphs.retrieval.links("1")
  end

  def test_a_foreign_ref_with_a_store_prefix_is_kept_as_written
    open_intent

    result = call("1", "cites", "global:25")

    assert_equal 0, result.code
    assert_equal "global:25", store_graphs.retrieval.links("1").first.to_ref
  end
end
