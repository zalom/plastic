# frozen_string_literal: true

# What the tests of a second home share: a roadmap or a context that a home holds as a file and no row.
module SecondHomeHelper
  FORM = "<!-- plastic roadmap form 2 -->"
  CONTEXT = "store/1--alpha/context.json"
  STAMP = Plastic::TestCase::STAMP

  def work = store_graphs.databases.fetch(:store)

  def sync = (@sync ||= Plastic::Graph::Knowledge::Sync.new(folder:, retrieval:, databases: store_graphs.databases))

  def plan = sync.plan(:up)

  def run_up = sync.apply(plan)

  def roadmap_text
    work.transaction do |batch|
      batch.put(:roadmaps, { slug: "plan", title: "Plan", goal: "Ship", opened_at: STAMP, updated_at: STAMP })
      batch.put(:batches, { roadmap: "plan", position: 1, title: "One", updated_at: STAMP })
      batch.put(:roadmap_items, { roadmap: "plan", item: "1", batch: 1, position: 1, title: "First", updated_at: STAMP })
    end
    Plastic::Graph::RoadmapPrint.new(retrieval, "plan").text
  end

  def forget_roadmap
    work.transaction do |batch|
      %i[batches roadmap_items roadmap_edges roadmap_log].each { |table| batch.remove(table, roadmap: "plan") }
      batch.remove(:roadmaps, slug: "plan")
    end
  end

  def second_home_roadmap
    text = roadmap_text
    forget_roadmap
    write("roadmaps/plan.md", text)
  end

  def context_json(**fields) = JSON.generate({ "intent" => "1", "discovery" => { "a" => 1 }, "context" => { "b" => 2 } }.merge(fields.transform_keys(&:to_s)))

  def bare_roadmap_text
    writer = Plastic::Graph::Knowledge::Roadmap::Writer.new(store_graphs.databases, retrieval)
    bare = Plastic::Graph::Knowledge::Roadmap::Fields.new(nil, nil, nil)
    writer.create_roadmap("plan", title: "plan", goal: nil)
    writer.write_batch("plan", 1, fields: bare)
    writer.add_item("plan", "1", 1, fields: bare, needs: [])
    writer.add_item("plan", "2", 1, fields: bare, needs: ["1"])
    writer.add_log("plan", "a note")
    Plastic::Graph::RoadmapPrint.new(retrieval, "plan").text
  end
end
