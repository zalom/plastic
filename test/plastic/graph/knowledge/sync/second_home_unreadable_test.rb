# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeSyncSecondHomeUnreadableTest < Plastic::TestCase
  include SecondHomeHelper

  fixtures :alpha_synced

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
