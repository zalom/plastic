# frozen_string_literal: true

# What the tests of the sync steps share: a plan as the steps read it, the work graph that serves it, and one run of a sync.
module SyncStepsHelper
  DECLARED = %i[overwrite merge failure conflicts merging unreadable unreadable_files unreadable_path unreadable_rowless lines].freeze

  # A clean plan with one write pending; a test overrides the fields it is about.
  CLEAN = { failure: nil, conflicts: [], merging: false, pending: 1, unreadable: [], unreadable_files: {}, rowless_files: [], new_types: [], direction: :up }.freeze

  Plan = Data.define(:failure, :conflicts, :merging, :pending, :unreadable, :unreadable_files, :rowless_files, :old_savepoints, :new_types, :direction) do
    def self.clean(**fields) = new(**CLEAN, old_savepoints: Plastic::Graph::Knowledge::Sync::OldSavepoints.none, **fields)

    def merging? = merging
  end

  # The settings a sync reads: the plans skip no file type, so a notice reads no setting.
  Settings = Data.define(:config)

  # The work graph as a sync calls it: each plan has the writes pending until the apply.
  class Work
    attr_reader :calls

    def initialize(plan)
      @plan = plan
      @calls = []
    end

    def sync_plan(direction, options)
      @calls << [:plan, direction, options]
      @plan.with(direction:)
    end

    def sync_apply(plan)
      @calls << [:apply]
      @plan = plan.with(pending: 0)
      ["read a.md"]
    end
  end

  def sync_context(plan, options)
    work = Work.new(Plan.clean(**plan))
    facts = { overwrite: false, merge: false }.merge(options)
    harness = Plastic::Context::Harness.new(nil, nil, Settings.new(config: nil))
    [Plastic::Context.new(declared: DECLARED, facts:, graphs: { work: }, harness:), work]
  end

  def run_sync(flow, plan: {}, **options)
    context, work = sync_context(plan, options)
    [flow.call(context), context.printed, work.calls]
  end

  def stop_sync(flow, kind, plan: {}, **options)
    context, work = sync_context(plan, options)
    [assert_raises(kind) { flow.call(context) }, context.printed, work.calls]
  end
end
