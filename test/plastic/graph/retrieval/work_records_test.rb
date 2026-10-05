# frozen_string_literal: true

require_relative "../../../test_helper"

module RetrievalRoadmapFixtures
  def roadmap_fields(title)
    Plastic::Graph::Knowledge::Roadmap::Fields.new(title:, goal: "Deliver #{title}", done: ["Verify #{title}"])
  end

  def seed_roadmap
    work.write_batch("delivery", 2, fields: roadmap_fields("Later"))
    work.write_batch("delivery", 1, fields: roadmap_fields("First"))
    work.add_item("delivery", "a", 1, fields: roadmap_fields("Evidence"), after: [])
    work.add_item("delivery", "b", 2, fields: roadmap_fields("Review"), after: ["a"])
    work.add_log("delivery", "First entry")
    work.add_log("delivery", "Second entry")
  end

  def work = store_graphs.work
end

class RetrievalRoadmapRecordsTest < Plastic::TestCase
  include RetrievalRoadmapFixtures

  def test_reads_a_missing_roadmap_without_inventing_records
    assert_nil retrieval.roadmap("absent")
    assert_equal [[], [], [], []], [retrieval.batches("absent"), retrieval.roadmap_items("absent"),
      retrieval.roadmap_edges("absent"), retrieval.roadmap_log("absent")]
  end

  def test_reads_the_roadmap_and_batches_in_position_order
    seed_roadmap

    assert_equal "delivery", retrieval.roadmap("delivery").slug
    assert_equal [1, 2], retrieval.batches("delivery").map(&:position)
  end

  def test_preserves_item_order_dependencies_and_log_order
    seed_roadmap

    assert_equal %w[a b], retrieval.roadmap_items("delivery").map(&:item)
    assert_equal [["a", "b"]], retrieval.roadmap_edges("delivery").map { |edge| [edge.from, edge.to] }
    assert_equal ["First entry", "Second entry"], retrieval.roadmap_log("delivery").map(&:text)
  end

  def test_starting_a_roadmap_item_indexes_its_spec_as_immutable_evidence
    seed_roadmap
    intent_id, problem, kind = work.start_roadmap_item("delivery", "a")
    document = retrieval.fetch_reference(retrieval.reference(intent_id, "spec.md"))

    assert_equal ["1", nil, nil], [intent_id, problem, kind]
    assert_includes document.fetch(:body), "Verify Evidence"
    assert_equal Digest::SHA256.hexdigest(document.fetch(:body)), document.fetch(:revision)
  end
end

class RetrievalBackupRecordsTest < Plastic::TestCase
  def test_reads_backup_metadata
    row = { name: "alpha/20260101100000", files: 3, bytes: 7, sha256: Digest::SHA256.hexdigest("archive"), at: STAMP, session_id: "fixture" }
    store_graphs.databases.fetch(:home).transaction { |batch| batch.put(:backups, row, statement: :insert) }

    assert_equal ["alpha/20260101100000"], retrieval.backups.map(&:name)
  end
end
