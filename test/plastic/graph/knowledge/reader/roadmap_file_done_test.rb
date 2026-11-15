# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeReaderRoadmapFileDoneTest < Plastic::TestCase
  RoadmapFile = Plastic::Graph::Knowledge::Reader::RoadmapFile

  def work = store_graphs.databases.fetch(:work)

  def seed
    work.transaction do |batch|
      batch.put(:roadmaps, { slug: "plan", title: "Plan", opened_at: STAMP, updated_at: STAMP })
      batch.put(:batches, { roadmap: "plan", position: 1, title: "One", done: "", updated_at: STAMP })
      batch.put(:roadmap_items, { roadmap: "plan", item: "1", batch: 1, position: 1, title: "First", done: "", updated_at: STAMP })
    end
  end

  def reread
    text = Plastic::Graph::RoadmapPrint.new(retrieval, "plan").text
    work.transaction do |batch|
      %i[roadmaps batches roadmap_items].each { |table| batch.remove(table, **{ ((table == :roadmaps) ? :slug : :roadmap) => "plan" }) }
    end
    work.transaction { |batch| RoadmapFile.new("plan", text).apply(batch) }
  end

  def test_an_item_with_no_done_lines_reads_back_with_the_empty_done_the_writer_stores
    seed
    reread

    assert_equal "", retrieval.roadmap_items("plan").first.done
  end

  def test_a_batch_with_no_done_lines_reads_back_with_the_empty_done_the_writer_stores
    seed
    reread

    assert_equal "", retrieval.batches("plan").first.done
  end
end
