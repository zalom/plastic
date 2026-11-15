# frozen_string_literal: true

# What the tests of the sync steps share: a plan as the steps read it, the work graph that serves it, and one run of a sync.
module SyncStepsHelper
  DECLARED = %i[overwrite merge failure conflicts merging unreadable unreadable_files unreadable_path unreadable_rowless lines].freeze

  Plan = Data.define(:failure, :conflicts, :merging, :pending, :unreadable, :unreadable_files, :rowless_files) do
    def initialize(unreadable_files: {}, rowless_files: [], **fields) = super

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
end
