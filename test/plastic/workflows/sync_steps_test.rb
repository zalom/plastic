# frozen_string_literal: true

require_relative "../support/kernel"
require_relative "../../../scripts/lib/plastic/workflows/registry"
require_relative "../../../scripts/lib/plastic/workflows/sync_up"
require_relative "../../../scripts/lib/plastic/workflows/sync_down"

class SyncStepsTest < Minitest::Test
  DECLARED = %i[overwrite merge failure conflicts merging lines].freeze
  PLAIN = "changed on both sides since the last print, nothing written: a.md, b.md; pass --overwrite PATH, --overwrite or --merge"
  LEFT = "changed on both sides since the last print, left as they are: a.md; pass --overwrite PATH or --overwrite"

  # A plan as the steps read it.
  Plan = Data.define(:failure, :conflicts, :merging, :pending) do
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
    work = Work.new(Plan.new(failure: nil, conflicts: [], merging: false, pending: 1, **plan))
    facts = { overwrite: false, merge: false }.merge(options)
    context = Plastic::Context.new(declared: DECLARED, facts:, graphs: { work: })
    [flow.call(context), context.printed, work.calls]
  end

  def test_a_clean_sync_applies_and_says_what_it_did
    outcome, printed, calls = run_sync(Plastic::Workflows::SyncUp)

    assert_equal [:done, ["read a.md"]], [outcome, printed]
    assert_equal [:plan, :up, { overwrite: false, merge: false }], calls.first
    assert_equal 1, calls.count([:apply])
  end

  def test_sync_down_plans_down_with_the_options_given
    _outcome, _printed, calls = run_sync(Plastic::Workflows::SyncDown, overwrite: "a.md", merge: true)

    assert_equal [:plan, :down, { overwrite: "a.md", merge: true }], calls.first
  end

  def test_a_level_store_applies_nothing
    outcome, printed, calls = run_sync(Plastic::Workflows::SyncUp, plan: { pending: 0 })

    assert_equal [:done, [], false], [outcome, printed, calls.include?([:apply])]
  end

  def test_a_failure_stops_before_the_apply
    outcome, _printed, calls = run_sync(Plastic::Workflows::SyncUp, plan: { failure: "INDEX.md waits" })

    assert_equal [Plastic::Failed, "code_sync_up, gate: INDEX.md waits", false], [outcome.class, outcome.message, calls.include?([:apply])]
  end

  def test_a_plain_call_with_conflicts_is_refused_before_it_writes
    outcome, _printed, calls = run_sync(Plastic::Workflows::SyncDown, plan: { conflicts: %w[a.md b.md] })

    assert_equal [Plastic::Refused, PLAIN, false], [outcome.class, outcome.message, calls.include?([:apply])]
  end

  def test_a_merge_applies_then_refuses_on_the_conflicts_left
    outcome, printed, = run_sync(Plastic::Workflows::SyncUp, plan: { conflicts: %w[a.md], merging: true })

    assert_equal [Plastic::Refused, LEFT, ["read a.md"]], [outcome.class, outcome.message, printed]
  end

  def test_each_direction_names_what_it_settles
    assert_equal [["plastic continue", "the rows hold every file changed by hand"], ["plastic continue", "the files hold every row that changed"]],
      [Plastic::Workflows::SyncUp, Plastic::Workflows::SyncDown].map { |flow| [flow.outcomes.first.offers, flow.outcomes.first.because] }
  end

  def test_the_registry_lists_the_storage_workflows
    assert_equal %i[code_write_intent code_sync_up code_sync_down], Plastic::Workflows::REGISTRY
  end
end
