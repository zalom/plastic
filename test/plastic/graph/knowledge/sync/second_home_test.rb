# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeSyncSecondHomeTest < Plastic::TestCase
  include SecondHomeHelper

  fixtures :alpha_synced

  def test_a_roadmap_file_with_no_row_is_read_into_rows
    second_home_roadmap

    assert_includes run_up, "read roadmaps/plan.md"
    assert_equal ["Plan", ["First"]], [retrieval.roadmap("plan").title, retrieval.roadmap_items("plan").map(&:title)]
  end

  def test_a_read_roadmap_is_counted_as_pending_before_it_is_read_and_not_after
    second_home_roadmap

    assert_equal [1, 0], [plan.pending, run_up && plan.pending]
  end

  def test_a_roadmap_written_with_every_optional_field_left_out_is_read_on_a_second_home
    text = bare_roadmap_text
    forget_roadmap
    write("roadmaps/plan.md", text)

    assert_empty plan.unreadable_files
    run_up

    assert_equal [[nil, nil], [%w[1 2 after]], ["a note"]], [retrieval.roadmap_items("plan").map(&:title), edges_of_plan, retrieval.roadmap_log("plan").map(&:text)]
  end

  def edges_of_plan = retrieval.roadmap_edges("plan").map { |edge| [edge.from, edge.to, edge.kind] }

  def test_a_roadmap_file_with_rows_is_not_read_again
    text = roadmap_text
    write("roadmaps/plan.md", text)

    refute_includes run_up, "read roadmaps/plan.md"
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

  def test_a_context_json_with_a_row_that_differs_from_its_print_replaces_the_row
    write(CONTEXT, context_json)
    run_up
    write(CONTEXT, context_json(context: { "b" => 3 }))
    run_up

    assert_equal({ "b" => 3 }, JSON.parse(retrieval.contexts("1").first.data))
  end
end

class KnowledgeSyncSecondHomeListingTest < Plastic::TestCase
  include SecondHomeHelper

  fixtures :alpha_synced

  def rows_of_the_second_home
    { roadmap: retrieval.roadmap("plan")&.title, old: retrieval.roadmap("old"), batches: retrieval.batches("plan").map(&:position),
      items: retrieval.roadmap_items("plan").map(&:item), **context_rows }
  end

  def context_rows = { intents: retrieval.intents.map(&:intent_id), contexts: retrieval.contexts("1").size, discoveries: retrieval.discoveries("1").size }

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

  def test_only_the_files_of_a_second_home_are_files_this_home_holds_no_rows_for
    write("store/1--alpha/graph.json", "junk")
    write("roadmaps/old.md", "# Old\n")

    assert_equal [%w[roadmaps/old.md store/1--alpha/graph.json], %w[roadmaps/old.md]], [plan.unreadable_files.keys.sort, plan.rowless_files]
  end

  def test_the_overwrite_offered_for_a_file_this_home_holds_rows_for_prints_it_and_the_next_sync_up_reads_clean
    graph = "store/1--alpha/graph.json"
    write(graph, "junk")

    assert_equal [[graph], []], [plan.unreadable_files.keys, plan.rowless_files]
    sync.apply(sync.plan(:down, overwrite: graph))

    assert_empty sync.plan(:up).unreadable_files
  end

  def test_a_cluster_that_names_an_intent_this_home_lacks_is_a_broken_part
    write("store/index.json", JSON.generate(JSON.parse(folder.read("store/index.json")).merge("clusters" => [{ "name" => "Core", "intents" => ["99"] }])))

    assert_includes plan.unreadable_files.fetch("store/index.json"), "99"
  end
end

class KnowledgeSyncSecondHomeReachTest < Plastic::TestCase
  fixtures :alpha_synced

  SecondHome = Plastic::Graph::Knowledge::Sync::SecondHome

  def test_a_second_home_that_is_not_active_reads_nothing
    none = SecondHome::NONE

    assert_equal [{}, [], 0], [none.problems, none.paths, none.size]
  end

  def test_a_context_json_of_an_archived_intent_listed_in_the_index_is_read
    write("store/index.json", JSON.generate("store" => "global", "origin_id" => "other-home", "clusters" => [],
      "intents" => [{ "intent_id" => "2", "origin_id" => "other-home", "slug" => "beta", "title" => "Beta", "status" => "done" }],
      "archives" => [{ "intent_id" => "2", "at" => STAMP, "session_id" => "s2", "completion" => nil }]))
    write("store/2--beta/context.json", JSON.generate("intent" => "2", "discovery" => { "a" => 1 }, "context" => { "b" => 2 }))

    assert_includes SecondHome.new(folder, retrieval).paths, "store/2--beta/context.json"
  end

  def test_a_second_home_with_clusters_counts_only_its_paths_because_the_clusters_are_a_part_entry
    write("store/index.json", JSON.generate(JSON.parse(folder.read("store/index.json")).merge("clusters" => [{ "name" => "Core", "intents" => ["1"] }])))

    assert_equal 0, SecondHome.new(folder, retrieval).size
  end
end

class KnowledgeSyncSecondHomeUnreadableTest < Plastic::TestCase
  include SecondHomeHelper

  fixtures :alpha_synced

  def test_a_roadmap_file_in_an_older_form_is_named_and_left_as_it_is
    write("roadmaps/old.md", "# Old\n\n## Goal\n\nShip\n")

    assert_includes plan.unreadable_files.fetch("roadmaps/old.md"), "older form"
    run_up

    assert_equal ["# Old\n\n## Goal\n\nShip\n", nil], [folder.read("roadmaps/old.md"), retrieval.roadmap("old")]
  end

  def test_the_log_file_beside_a_roadmap_is_not_a_roadmap_and_stays_as_it_is
    write("roadmaps/old.savepoint.md", "2026-09-05T08:06:00Z  created  Roadmap created\n")

    refute_includes plan.unreadable_files.keys, "roadmaps/old.savepoint.md"
    run_up

    assert_equal "2026-09-05T08:06:00Z  created  Roadmap created\n", folder.read("roadmaps/old.savepoint.md")
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

  def test_a_context_json_that_is_not_json_is_a_broken_part_left_as_it_is_and_the_roadmap_is_read
    write(CONTEXT, "{nope")
    second_home_roadmap

    assert_includes plan.unreadable_files.fetch(CONTEXT), "not JSON"
    run_up

    assert_equal [["Plan"], [], "{nope"], [[retrieval.roadmap("plan").title], retrieval.contexts("1"), folder.read(CONTEXT)]
  end

  def test_a_context_json_is_read_while_a_roadmap_file_is_broken
    write("roadmaps/old.md", "# Old\n")
    write(CONTEXT, context_json)

    assert_equal [CONTEXT], Plastic::Graph::Knowledge::Sync::SecondHome.new(folder, retrieval).paths
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
end
