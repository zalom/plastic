# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeIntentWriterTest < Plastic::TestCase
  def writer(session: nil) = Plastic::Graph::Knowledge::Intent::Writer.new(store_graphs.databases, retrieval, folder, session:)

  def test_a_plain_call_has_no_problem
    assert_nil writer.problem
  end

  def test_a_legacy_store_must_be_imported_first
    write("INDEX.md", "# Index\n")

    assert_equal "this store still has INDEX.md; run plastic sync up to import it first", writer.problem
  end

  def test_a_hand_edited_index_must_be_read_first
    open_intent
    write("store/index.json", "{}\n")

    assert_equal [true, "store/index.json changed by hand since the last print; run plastic sync up to read it first"],
      [writer.hand_edited?, writer.problem]
  end

  def test_a_printed_index_is_not_hand_edited
    refute_predicate writer, :hand_edited?
    open_intent

    refute_predicate writer, :hand_edited?
  end

  def test_only_the_new_statuses_are_taken
    assert_equal ["a new intent takes the status open, active, parked or future, not done", nil, nil, nil],
      %w[done active parked future].map { |status| writer.problem(status:) }
  end

  def test_the_parent_must_exist
    assert_equal "no intent 9 in this store to be the parent", writer.problem(parent_id: "9")
    open_intent

    assert_nil writer.problem(parent_id: "1")
  end

  def test_a_ref_to_a_missing_intent_of_this_installation_is_a_problem
    assert_equal ["no intent 5 of this installation for the ref", nil], ["5-#{origin}", "ENG-1"].map { |ref| writer.problem(ref:) }
  end

  def test_write_takes_the_next_id_and_the_defaults
    first = writer.write(title: "Build the thing")
    child = writer.write(title: "Child", parent_id: "1", kind: "research", status: nil, slug: "kid")

    assert_equal ["1", nil, "build-the-thing", "work", "open"], first.to_h.values_at(:intent_id, :parent_id, :slug, :kind, :status)
    assert_equal %w[1a 1 kid research open], child.to_h.values_at(:intent_id, :parent_id, :slug, :kind, :status)
    assert_equal first.opened_at, first.updated_at
  end

  def test_write_adds_the_first_savepoint_line_and_the_own_file
    writer.write(title: "Alpha")

    assert_equal ["Opened: Alpha"], retrieval.savepoints("1").map(&:text)
    assert_equal ["1--alpha.md"], retrieval.documents("1").map(&:path)
  end

  def test_write_carries_the_session_onto_the_first_savepoint_line
    writer(session: "s-1").write(title: "Alpha")

    assert_equal "s-1", retrieval.savepoints("1").first.session_id
  end

  def test_the_ref_line_says_what_a_ref_names
    assert_equal ["ref: intent 1 of this installation", "ref: ENG-1"], ["1-#{origin}", "ENG-1"].map { |ref| writer.ref_line(ref) }
  end
end
