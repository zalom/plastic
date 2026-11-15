# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeSyncSecondHomeTest < Plastic::TestCase
  fixtures :alpha_synced

  FORM = "<!-- plastic roadmap form 2 -->"
  CONTEXT = "store/1--alpha/context.json"

  def work = store_graphs.databases.fetch(:work)

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

  def test_a_roadmap_file_with_no_row_is_read_into_rows
    second_home_roadmap

    assert_includes run_up, "read roadmaps/plan.md"
    assert_equal ["Plan", ["First"]], [retrieval.roadmap("plan").title, retrieval.roadmap_items("plan").map(&:title)]
  end

  def test_a_read_roadmap_is_counted_as_pending_before_it_is_read_and_not_after
    second_home_roadmap

    assert_equal [1, 0], [plan.pending, run_up && plan.pending]
  end

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

  def test_a_roadmap_written_with_every_optional_field_left_out_is_read_on_a_second_home
    text = bare_roadmap_text
    forget_roadmap
    write("roadmaps/plan.md", text)

    assert_empty plan.unreadable_files
    run_up

    assert_equal [[nil, nil], [%w[1 2 after]], ["a note"]],
      [retrieval.roadmap_items("plan").map(&:title), retrieval.roadmap_edges("plan").map { |edge| [edge.from, edge.to, edge.kind] }, retrieval.roadmap_log("plan").map(&:text)]
  end

  def test_a_roadmap_file_with_rows_is_not_read_again
    text = roadmap_text
    write("roadmaps/plan.md", text)

    refute_includes run_up, "read roadmaps/plan.md"
  end

  def test_a_roadmap_file_in_an_older_form_is_named_and_left_as_it_is
    write("roadmaps/old.md", "# Old\n\n## Goal\n\nShip\n")

    assert_includes plan.unreadable_files.fetch("roadmaps/old.md"), "older form"
    run_up

    assert_equal ["# Old\n\n## Goal\n\nShip\n", nil], [folder.read("roadmaps/old.md"), retrieval.roadmap("old")]
  end

  def test_a_roadmap_file_with_an_unknown_form_line_is_named_as_an_older_form
    write("roadmaps/odd.md", "<!-- plastic roadmap form 9 -->\n")

    assert_includes plan.unreadable_files.fetch("roadmaps/odd.md"), "older form"
  end

  def test_a_roadmap_file_that_names_another_slug_is_named_with_the_reason
    text = roadmap_text
    forget_roadmap
    write("roadmaps/other.md", text)

    assert_includes plan.unreadable_files.fetch("roadmaps/other.md"), "names the slug plan, not other"
  end

  def test_a_context_json_with_a_row_is_not_read_again_by_the_second_home
    write(CONTEXT, context_json)
    run_up

    assert_empty Plastic::Graph::Knowledge::Sync::SecondHome.new(folder, retrieval).paths
  end

  def test_a_context_json_with_no_row_is_read_into_the_context_and_discovery_rows
    write(CONTEXT, context_json)

    assert_includes run_up, "read #{CONTEXT}"
    assert_equal [{ "a" => 1 }, { "b" => 2 }], [JSON.parse(retrieval.discoveries("1").first.data), JSON.parse(retrieval.contexts("1").first.data)]
  end

  def test_a_context_json_with_a_row_is_not_read_again
    write(CONTEXT, context_json)
    run_up
    write(CONTEXT, context_json(context: { "b" => 3 }))
    run_up

    assert_equal({ "b" => 2 }, JSON.parse(retrieval.contexts("1").first.data))
  end

  def test_a_context_json_that_is_not_json_is_a_broken_part_left_as_it_is_and_the_roadmap_is_read
    write(CONTEXT, "{nope")
    second_home_roadmap

    assert_includes plan.unreadable_files.fetch(CONTEXT), "not JSON"
    run_up

    assert_equal [["Plan"], [], "{nope"], [[retrieval.roadmap("plan").title], retrieval.contexts("1"), folder.read(CONTEXT)]
  end

  def rows_of_the_second_home
    { roadmap: retrieval.roadmap("plan")&.title, old: retrieval.roadmap("old"), batches: retrieval.batches("plan").map(&:position),
      items: retrieval.roadmap_items("plan").map(&:item), intents: retrieval.intents.map(&:intent_id),
      contexts: retrieval.contexts("1").size, discoveries: retrieval.discoveries("1").size }
  end

  def test_the_clusters_are_read_while_another_part_is_broken
    write("roadmaps/old.md", "# Old\n")
    write("store/index.json", JSON.generate(JSON.parse(folder.read("store/index.json")).merge("clusters" => [{ "name" => "Core", "intents" => ["1"] }])))

    assert_equal "store/index.json", Plastic::Graph::Knowledge::Sync::SecondHome.new(folder, retrieval, nil).cluster_read.path
  end

  def test_a_context_json_is_read_while_a_roadmap_file_is_broken
    write("roadmaps/old.md", "# Old\n")
    write(CONTEXT, context_json)

    assert_equal [CONTEXT], Plastic::Graph::Knowledge::Sync::SecondHome.new(folder, retrieval).paths
  end

  def test_a_broken_part_is_listed_and_every_good_part_is_read_into_every_table
    write(CONTEXT, context_json)
    write("roadmaps/old.md", "# Old\n")
    second_home_roadmap

    assert_equal %w[roadmaps/old.md], plan.unreadable_files.keys
    run_up

    assert_equal({ roadmap: "Plan", old: nil, batches: [1], items: %w[1], intents: ["1"], contexts: 1, discoveries: 1 }, rows_of_the_second_home)
    assert_equal %w[roadmaps/old.md], plan.unreadable_files.keys
  end

  def test_a_broken_part_is_counted_as_pending_only_for_what_is_still_to_read
    write("roadmaps/old.md", "# Old\n")
    second_home_roadmap

    assert_equal [1, 0], [plan.pending, run_up && plan.pending]
  end

  def test_a_context_json_that_names_another_intent_is_a_broken_part
    write(CONTEXT, context_json(intent: "2"))

    assert_includes plan.unreadable_files.fetch(CONTEXT), "intent 2"
  end

  def test_every_broken_part_is_named_in_one_run
    write(CONTEXT, "{nope")
    write("roadmaps/old.md", "# Old\n")

    assert_equal ["roadmaps/old.md", CONTEXT], plan.unreadable_files.keys.sort
  end

  def test_the_clusters_of_the_index_are_read_when_this_home_holds_none
    second_home = Plastic::Graph::Knowledge::Sync::SecondHome.new(folder, retrieval, nil)
    write("store/index.json", JSON.generate(JSON.parse(folder.read("store/index.json")).merge("clusters" => [{ "name" => "Core", "intents" => ["1"] }])))

    assert_equal "store/index.json", second_home.cluster_read.path
  end

  def test_a_cluster_that_names_an_intent_this_home_lacks_is_a_broken_part
    write("store/index.json", JSON.generate(JSON.parse(folder.read("store/index.json")).merge("clusters" => [{ "name" => "Core", "intents" => ["99"] }])))

    assert_includes plan.unreadable_files.fetch("store/index.json"), "99"
  end
end
