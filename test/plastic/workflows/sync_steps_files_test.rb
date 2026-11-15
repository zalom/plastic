# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/workflows/registry"
require_relative "../../../lib/plastic/workflows/code/sync/up"
require_relative "../../../lib/plastic/workflows/code/sync/down"

class SyncStepsFilesTest < Plastic::TestCase
  include SyncStepsHelper

  ROWLESS = "roadmaps/old.md: roadmaps/old.md is in an older form that this release does not read; " \
            "the home that holds the rows prints the file again with plastic sync down, and the file is then copied here again"
  PRINTED_OVER = "printed again from rows: roadmaps/r1.md; it is generated from rows, and a change made outside Plastic is not kept"

  def test_an_unreadable_graph_file_is_listed_and_stops_the_sync_with_the_overwrite
    files = { "store/1--alpha/graph.json" => "junk" }
    outcome, = run_sync(Plastic::Workflows::Code::Sync::Up, plan: { unreadable_files: files })

    assert_instance_of Plastic::Failed, outcome
    assert_includes outcome.message, "store/1--alpha/graph.json: junk; run plastic sync down --overwrite store/1--alpha/graph.json"
    assert_equal "plastic sync down --overwrite store/1--alpha/graph.json", outcome.next_command
  end

  def test_a_file_this_home_holds_no_rows_for_is_listed_with_no_command_to_run_here
    files = { "roadmaps/old.md" => "roadmaps/old.md is in an older form that this release does not read" }
    outcome, = run_sync(Plastic::Workflows::Code::Sync::Up, plan: { unreadable_files: files, rowless_files: files.keys })

    assert_instance_of Plastic::Failed, outcome
    assert_includes outcome.message, ROWLESS
    assert_nil outcome.next_command
  end

  def test_a_file_this_home_holds_no_rows_for_is_offered_no_overwrite
    files = { "roadmaps/old.md" => "older" }
    outcome, = run_sync(Plastic::Workflows::Code::Sync::Up, plan: { unreadable_files: files, rowless_files: files.keys })

    refute_includes outcome.message, "--overwrite"
  end

  def test_a_file_with_rows_here_keeps_its_command_when_another_file_has_none
    files = { "roadmaps/old.md" => "older", "store/1--alpha/graph.json" => "junk" }
    outcome, = run_sync(Plastic::Workflows::Code::Sync::Up, plan: { unreadable_files: files, rowless_files: %w[roadmaps/old.md] })

    assert_equal "plastic sync down --overwrite store/1--alpha/graph.json", outcome.next_command
    assert_includes outcome.message, "roadmaps/old.md: older; the home that holds the rows prints the file again"
  end

  def test_a_view_printed_over_is_named_with_what_happened_to_the_change
    outcome, printed, = run_sync(Plastic::Workflows::Code::Sync::Up, plan: { printed_over: ["roadmaps/r1.md"] })

    assert_equal [:printed_again, ["read a.md", PRINTED_OVER]], [outcome, printed]
  end

  def test_each_unreadable_file_is_listed_with_its_own_overwrite
    files = { "store/1--alpha/graph.json" => "junk", "store/2--beta/graph.json" => "junk too" }
    outcome, = run_sync(Plastic::Workflows::Code::Sync::Up, plan: { unreadable_files: files })

    assert_includes outcome.message, "store/1--alpha/graph.json: junk; run plastic sync down --overwrite store/1--alpha/graph.json\n"
    assert_includes outcome.message, "store/2--beta/graph.json: junk too; run plastic sync down --overwrite store/2--beta/graph.json"
    refute_includes outcome.message, "with the command below"
  end
end
