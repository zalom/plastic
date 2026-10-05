# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../scripts/lib/plastic/graph/knowledge/archive/writer"

class KnowledgeArchiveGuardTest < Plastic::TestCase
  def setup
    super
    @work = store_graphs.work
    @target = @work.write_intent(title: "Target", status: "done")
  end

  def problem = Plastic::Graph::Knowledge::Archive::Guard.new(retrieval).problem(retrieval.intent(@target.intent_id))

  def linked_from(status)
    source = @work.write_intent(title: "Source", status:)
    @work.add_link(from_ref: source.intent_id, to_ref: @target.intent_id, kind: "chain")
    source
  end

  def test_a_done_intent_nothing_live_links_to_may_archive
    assert_nil problem
  end

  def test_an_open_intent_is_refused_by_its_status
    open = @work.write_intent(title: "Open")

    assert_equal "intent 2 is open; only done, abandoned and future intents archive",
      Plastic::Graph::Knowledge::Archive::Guard.new(retrieval).problem(open)
  end

  def test_a_link_from_a_live_intent_is_refused
    linked_from("open")

    assert_equal "intent 2 links to 1", problem
  end

  def test_a_link_from_a_done_intent_does_not_hold_it
    linked_from("abandoned")

    assert_nil problem
  end

  def test_a_link_from_an_archived_intent_does_not_hold_it
    source = linked_from("future")
    store_graphs.databases[:work].transaction do |batch|
      batch.put(:archives, { intent_id: source.intent_id, at: STAMP, restored_at: nil, session_id: nil })
    end

    assert_nil problem
  end
end
