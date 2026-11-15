# frozen_string_literal: true

# What the tests of the roadmap file reader share: a seeded roadmap, its print, and a read of text into the rows.
module RoadmapFileHelper
  RoadmapFile = Plastic::Graph::Knowledge::Reader::RoadmapFile
  FORM = "<!-- plastic roadmap form 2 -->"
  TRICKY = "# Not a title\n## Batch 9\n- [x] 3 Other \\ back — done\n  item: fake"
  STAMP = Plastic::TestCase::STAMP

  def work = store_graphs.databases.fetch(:work)

  def seed(title: TRICKY, item_title: "Hello — world — ready", goal: "Line one\nLine two")
    work.transaction do |batch|
      batch.put(:roadmaps, { slug: "plan", title:, goal:, opened_at: STAMP, updated_at: STAMP })
      batch.put(:batches, { roadmap: "plan", position: 1, title:, goal:, done: "first\nsecond", updated_at: STAMP })
      batch.put(:roadmap_items, { roadmap: "plan", item: "1", batch: 1, position: 1, title: item_title, goal:, done: "d", mark: "dropped", updated_at: STAMP })
      batch.put(:roadmap_items, { roadmap: "plan", item: "2", batch: 1, position: 2, title: "Second", updated_at: STAMP })
      batch.put(:roadmap_edges, { roadmap: "plan", from: "1", to: "2", kind: "after" })
      batch.put(:roadmap_log, { roadmap: "plan", position: 1, at: STAMP, text: TRICKY, session_id: "s1" })
    end
  end

  def printed = Plastic::Graph::RoadmapPrint.new(retrieval, "plan").text

  def clear
    work.transaction do |batch|
      %i[roadmaps batches roadmap_items roadmap_edges roadmap_log].each do |table|
        batch.remove(table, **{ ((table == :roadmaps) ? :slug : :roadmap) => "plan" })
      end
    end
  end

  def read(text) = work.transaction { |batch| RoadmapFile.new("plan", text).apply(batch) }
end
