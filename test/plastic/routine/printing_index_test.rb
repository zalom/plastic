# frozen_string_literal: true

require_relative "../../test_helper"

class RoutinePrintingIndexTest < Plastic::TestCase
  include LifecycleHelper
  include HandEditHelper

  def test_an_edited_index_refuses_intent_new_with_no_intent_written
    open_intent
    write("store/index.json", "{}\n")
    result = cli("intent", "new", "Second")

    assert_refused(result, "store/index.json")
    assert_nil retrieval.intent("2")
  end

  def open_roadmap
    cli("roadmap", "new", "r1")
    cli("roadmap", "batch", "r1", "1", "--title", "T", "--goal", "Batch goal", "--done", "batch done")
    cli("roadmap", "add", "r1", "1", "a", "--title", "A", "--goal", "Item goal", "--done", "item done")
  end

  def test_an_edited_index_refuses_roadmap_open
    open_intent
    open_roadmap
    write("store/index.json", "{}\n")

    assert_refused(cli("roadmap", "open", "r1", "a"), "store/index.json")
  end

  def test_an_edited_roadmap_file_refuses_roadmap_open
    open_roadmap
    write("roadmaps/r1.md", "# by hand\n")

    assert_refused(cli("roadmap", "open", "r1", "a"), "roadmaps/r1.md")
  end
end
