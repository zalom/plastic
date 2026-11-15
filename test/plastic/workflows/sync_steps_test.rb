# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../support/second_load"
require_relative "../../../lib/plastic/workflows/registry"
require_relative "../../../lib/plastic/workflows/code/sync/up"
require_relative "../../../lib/plastic/workflows/code/sync/down"

class SyncStepsTest < Plastic::TestCase
  include SyncStepsHelper

  UP_PLAIN = "changed on both sides since the last print, nothing written. --overwrite PATH reads that file into rows, " \
             "--overwrite reads every file, --merge applies the one-sided changes and lists the rest. The records: a.md b.md"
  UP_LEFT = "changed on both sides since the last print, left as they are. --overwrite PATH reads that file into rows, " \
            "--overwrite reads every file. The records: a.md"
  DOWN_PLAIN = "changed on both sides since the last print, nothing written. --overwrite PATH prints that record's rows over the file, " \
               "--overwrite prints every record, --merge applies the one-sided changes and lists the rest. The records: a.md b.md"
  DOWN_LEFT = "changed on both sides since the last print, left as they are. --overwrite PATH prints that record's rows over the file, " \
              "--overwrite prints every record. The records: a.md"

  def test_a_clean_sync_applies_and_says_what_it_did
    outcome, printed, calls = run_sync(Plastic::Workflows::Code::Sync::Up)

    assert_equal [:done, ["read a.md"]], [outcome, printed]
    assert_equal [:plan, :up, { overwrite: false, merge: false }], calls.first
    assert_equal 1, calls.count([:apply])
  end

  def test_sync_down_plans_down_with_the_options_given
    _outcome, _printed, calls = run_sync(Plastic::Workflows::Code::Sync::Down, overwrite: "a.md", merge: true)

    assert_equal [:plan, :down, { overwrite: "a.md", merge: true }], calls.first
  end

  def test_a_level_store_applies_nothing
    outcome, printed, calls = run_sync(Plastic::Workflows::Code::Sync::Up, plan: { pending: 0 })

    assert_equal [:done, [], false], [outcome, printed, calls.include?([:apply])]
  end

  def test_a_failure_stops_before_the_apply
    outcome, _printed, calls = run_sync(Plastic::Workflows::Code::Sync::Up, plan: { failure: "INDEX.md waits" })

    assert_equal [Plastic::Failed, "code_sync_up, gate: INDEX.md waits", false], [outcome.class, outcome.message, calls.include?([:apply])]
  end

  def test_a_plain_sync_up_with_conflicts_is_refused_before_it_writes_and_ends_on_the_last_path
    outcome, _printed, calls = run_sync(Plastic::Workflows::Code::Sync::Up, plan: { conflicts: %w[a.md b.md] })

    assert_equal [Plastic::Refused, UP_PLAIN, false], [outcome.class, outcome.message, calls.include?([:apply])]
    assert_equal "b.md", outcome.message.split.last
  end

  def test_a_plain_sync_down_with_conflicts_is_refused_before_it_writes_and_ends_on_the_last_path
    outcome, _printed, calls = run_sync(Plastic::Workflows::Code::Sync::Down, plan: { conflicts: %w[a.md b.md] })

    assert_equal [Plastic::Refused, DOWN_PLAIN, false], [outcome.class, outcome.message, calls.include?([:apply])]
    assert_equal "b.md", outcome.message.split.last
  end

  def test_a_sync_up_merge_applies_then_refuses_on_the_conflicts_left
    outcome, printed, = run_sync(Plastic::Workflows::Code::Sync::Up, plan: { conflicts: %w[a.md], merging: true })

    assert_equal [Plastic::Refused, UP_LEFT, ["read a.md"]], [outcome.class, outcome.message, printed]
  end

  def test_a_sync_down_merge_applies_then_refuses_on_the_conflicts_left
    outcome, printed, = run_sync(Plastic::Workflows::Code::Sync::Down, plan: { conflicts: %w[a.md], merging: true })

    assert_equal [Plastic::Refused, DOWN_LEFT, ["read a.md"]], [outcome.class, outcome.message, printed]
  end

  def test_each_direction_names_what_it_settles
    assert_equal [["plastic next", "the rows hold every file changed by hand"], ["plastic next", "the files hold every row that changed"]],
      [Plastic::Workflows::Code::Sync::Up, Plastic::Workflows::Code::Sync::Down].map { |flow| [flow.ending(:done).offers, flow.ending(:done).because] }
  end

  def test_the_registry_lists_the_storage_workflows
    assert_equal %i[code_write_intent code_sync_up code_sync_down], Plastic::Workflows::REGISTRY.keys.first(3)
    assert_equal Plastic::Workflows::REGISTRY.size, Plastic::Workflows::REGISTRY.values.uniq.size
    assert_includes Plastic::Workflows::REGISTRY.keys, :code_preview_sync
  end

  def test_a_second_load_of_a_sync_class_keeps_one_chain
    up = Plastic::Workflows::Code::Sync::Up
    shape = -> { [up.steps.size, up.facts.size, up.outcome_names] }
    before = shape.call
    path = File.expand_path("../../../lib/plastic/workflows/code/sync/up.rb", __dir__)

    assert_equal %i[done], up.outcome_names
    assert SecondLoad.keeps?(path) { shape.call == before }
  end

  def test_a_sync_declares_its_steps_and_gates_in_order
    flow = Class.new(Plastic::CodeWorkflow) do
      extend Plastic::Workflows::SyncSteps

      sync :up
    end
    steps = Plastic::Workflows::SyncSteps
    gates = flow.steps.grep(Plastic::CodeWorkflow::Gate).map(&:reason)

    assert_equal ["plan the sync", "gate", "gate", "apply the changes", "say what changed", "gate", "gate", "gate", "gate"], flow.steps.map(&:name)
    assert_equal ["%{failure}", steps::REFUSED_BEFORE.fetch(:up), steps::REFUSED_AFTER.fetch(:up), steps::UNREADABLE, steps::UNREADABLE_FILES, steps::UNREADABLE_FILES], gates
    assert_equal ["plastic next"], flow.outcomes.map(&:offers)
  end

  def test_a_plan_note_clears_the_lines_of_an_earlier_apply
    context = Plastic::Context.new(declared: DECLARED, facts: { lines: ["read a.md"] }, graphs: {})
    Plastic::Workflows::SyncSteps.note(context, Plan.new(failure: nil, conflicts: [], merging: false, pending: 1, unreadable: []))

    assert_nil context.lines
  end
end

class SyncStepsFilesTest < Plastic::TestCase
  include SyncStepsHelper

  ROWLESS = "roadmaps/old.md: roadmaps/old.md is in an older form that this release does not read; " \
            "the home that holds the rows prints the file again with plastic sync down, and the file is then copied here again"

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

  def test_each_unreadable_file_is_listed_with_its_own_overwrite
    files = { "store/1--alpha/graph.json" => "junk", "store/2--beta/graph.json" => "junk too" }
    outcome, = run_sync(Plastic::Workflows::Code::Sync::Up, plan: { unreadable_files: files })

    assert_includes outcome.message, "store/1--alpha/graph.json: junk; run plastic sync down --overwrite store/1--alpha/graph.json\n"
    assert_includes outcome.message, "store/2--beta/graph.json: junk too; run plastic sync down --overwrite store/2--beta/graph.json"
    refute_includes outcome.message, "with the command below"
  end
end
