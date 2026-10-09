# frozen_string_literal: true

require_relative "../test_helper"

class PrintTriggerTest < Plastic::TestCase
  include LifecycleHelper

  def test_auto_prints_the_intent_files_and_the_index
    specified
    cli("intent", "approve", "1")
    result = cli("auto", "1")

    assert_equal [0, "active", true], [result.code, listed("1").fetch("status"), result.out.include?("files:")]
  end

  def test_end_rewrites_the_index_to_show_the_intent_done
    accepted_intent
    review_off
    cli("intent", "end", "1")

    assert_equal "done", listed("1").fetch("status")
  end

  def test_abandon_rewrites_the_index_to_show_the_intent_abandoned
    intent = open_intent
    write("#{intent.dir}/outcome.md", "# Outcome\n\nDropped: the need went away.\n\n## Verification\n- Reverted: nothing delivered\n")
    cli("sync", "up")
    cli("intent", "abandon", "1")

    assert_equal "abandoned", listed("1").fetch("status")
  end

  def test_archive_rewrites_the_index_without_the_intent
    open_intent
    store_graphs.databases.fetch(:work).transaction { |batch| batch.write(:intents, "UPDATE intents SET status = 'done'") }
    cli("intent", "archive", "1")

    assert_nil listed("1")
  end

  def test_a_call_that_wrote_only_its_run_row_leaves_a_hand_edited_graph_json_alone
    intent = specified
    cli("intent", "approve", "1")
    File.write(store_path("#{intent.dir}/graph.json"), '{"hand":true}')
    cli("intent", "approve", "1")

    assert_equal '{"hand":true}', File.read(store_path("#{intent.dir}/graph.json"))
  end

  def test_a_second_identical_call_prints_no_files_row
    specified

    assert_equal [true, false], %w[1 2].map { cli("intent", "approve", "1").out.include?("files:") }
  end
end
