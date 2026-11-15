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

  def test_a_context_json_with_a_row_is_not_read_again
    write(CONTEXT, context_json)
    run_up
    write(CONTEXT, context_json(context: { "b" => 3 }))
    run_up

    assert_equal({ "b" => 2 }, JSON.parse(retrieval.contexts("1").first.data))
  end
end
