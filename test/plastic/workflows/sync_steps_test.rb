# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/workflows/registry"
require_relative "../../../lib/plastic/workflows/code/sync/up"
require_relative "../../../lib/plastic/workflows/code/sync/down"

class SyncStepsTest < Plastic::TestCase
  DECLARED = %i[overwrite merge failure conflicts merging unreadable unreadable_files unreadable_path printed_over lines].freeze
  PLAIN = "changed on both sides since the last print, nothing written: a.md, b.md; pass --overwrite PATH, --overwrite or --merge"
  LEFT = "changed on both sides since the last print, left as they are: a.md; pass --overwrite PATH or --overwrite"

  # A plan as the steps read it.
  Plan = Data.define(:failure, :conflicts, :merging, :pending, :unreadable, :unreadable_files, :printed_over) do
    def initialize(unreadable_files: {}, printed_over: [], **fields) = super

    def merging? = merging
  end

  # The work graph as a sync calls it: each plan has the writes pending until the apply.
  class Work
    attr_reader :calls

    def initialize(plan)
      @plan = plan
      @calls = []
    end

    def sync_plan(direction, options)
      @calls << [:plan, direction, options]
      @plan
    end

    def sync_apply(plan)
      @calls << [:apply]
      @plan = plan.with(pending: 0)
      ["read a.md"]
    end
  end

  def run_sync(flow, plan: {}, **options)
    work = Work.new(Plan.new(failure: nil, conflicts: [], merging: false, pending: 1, unreadable: [], **plan))
    facts = { overwrite: false, merge: false }.merge(options)
    context = Plastic::Context.new(declared: DECLARED, facts:, graphs: { work: })
    [flow.call(context), context.printed, work.calls]
  end

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

  def test_a_plain_call_with_conflicts_is_refused_before_it_writes
    outcome, _printed, calls = run_sync(Plastic::Workflows::Code::Sync::Down, plan: { conflicts: %w[a.md b.md] })

    assert_equal [Plastic::Refused, PLAIN, false], [outcome.class, outcome.message, calls.include?([:apply])]
  end

  def test_a_merge_applies_then_refuses_on_the_conflicts_left
    outcome, printed, = run_sync(Plastic::Workflows::Code::Sync::Up, plan: { conflicts: %w[a.md], merging: true })

    assert_equal [Plastic::Refused, LEFT, ["read a.md"]], [outcome.class, outcome.message, printed]
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
    before = [Plastic::Workflows::Code::Sync::Up.steps.size, Plastic::Workflows::Code::Sync::Up.facts.size]
    load File.expand_path("../../../lib/plastic/workflows/code/sync/up.rb", __dir__)

    assert_equal [before, %i[printed_again done]], [[Plastic::Workflows::Code::Sync::Up.steps.size, Plastic::Workflows::Code::Sync::Up.facts.size], Plastic::Workflows::Code::Sync::Up.outcome_names]
  end

  def test_a_sync_declares_its_steps_and_gates_in_order
    flow = Class.new(Plastic::CodeWorkflow) do
      extend Plastic::Workflows::SyncSteps

      sync :up
    end
    steps = Plastic::Workflows::SyncSteps
    gates = flow.steps.grep(Plastic::CodeWorkflow::Gate).map(&:reason)

    assert_equal ["plan the sync", "gate", "gate", "apply the changes", "say what changed", "gate", "gate", "gate"], flow.steps.map(&:name)
    assert_equal ["%{failure}", steps::REFUSED_BEFORE, steps::REFUSED_AFTER, steps::UNREADABLE, steps::UNREADABLE_FILES], gates
    assert_equal ["plastic next", "plastic next"], flow.outcomes.map(&:offers)
  end

def test_an_unreadable_graph_file_is_listed_and_stops_the_sync_with_the_overwrite
  files = { "store/1--alpha/graph.json" => "junk" }
  outcome, = run_sync(Plastic::Workflows::Code::Sync::Up, plan: { unreadable_files: files })

  assert_instance_of Plastic::Failed, outcome
  assert_includes outcome.message, "store/1--alpha/graph.json: junk; run plastic sync down --overwrite store/1--alpha/graph.json"
  assert_equal "plastic sync down --overwrite store/1--alpha/graph.json", outcome.next_command
end

PRINTED_OVER = "printed again from rows: roadmaps/r1.md; it is generated from rows, and a change made outside Plastic is not kept"

def test_a_view_printed_over_is_named_with_what_happened_to_the_change
  outcome, printed, = run_sync(Plastic::Workflows::Code::Sync::Up, plan: { printed_over: ["roadmaps/r1.md"] })

  assert_equal [:printed_again, ["read a.md", PRINTED_OVER]], [outcome, printed]
end

def test_the_because_line_of_a_view_printed_over_claims_no_read
  because = Plastic::Workflows::Code::Sync::Up.ending(:printed_again).because

  assert_equal "the rows printed each generated file changed outside Plastic again, and hold every other file changed by hand", because
end

  def test_each_unreadable_file_is_listed_with_its_own_overwrite
    files = { "store/1--alpha/graph.json" => "junk", "store/2--beta/graph.json" => "junk too" }
    outcome, = run_sync(Plastic::Workflows::Code::Sync::Up, plan: { unreadable_files: files })

    assert_includes outcome.message, "store/1--alpha/graph.json: junk; run plastic sync down --overwrite store/1--alpha/graph.json\n"
    assert_includes outcome.message, "store/2--beta/graph.json: junk too; run plastic sync down --overwrite store/2--beta/graph.json"
    refute_includes outcome.message, "with the command below"
  end

  def test_a_plan_note_clears_the_lines_of_an_earlier_apply
    context = Plastic::Context.new(declared: DECLARED, facts: { lines: ["read a.md"] }, graphs: {})
    Plastic::Workflows::SyncSteps.note(context, Plan.new(failure: nil, conflicts: [], merging: false, pending: 1, unreadable: []))

    assert_nil context.lines
  end
end
