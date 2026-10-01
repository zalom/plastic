# encoding: UTF-8

require "timeout"
require "open3"
require_relative "../session_ledger"
require_relative "../session_backfill"

module SessionStartHook
  # File every unclosed prior day ledger into today, oldest first, at most 3
  # per boot within a 5-second budget (intent 301, spec D9). Each day runs
  # the sibling file-session-intent in its own rescue; the boot never blocks.
  module FirstBootSweep
    # One sweep run's fixed inputs: the sibling script to shell out to, the
    # templates it needs, and where/when it is filing a prior day into.
    Job = Struct.new(:filer, :templates, :store_dir, :today)

    def self.line(store_dir:)
      today = SessionLedger.day_id
      filed, candidates = run_candidates(store_dir, today)
      return nil unless filed.positive?

      describe(filed, candidates, today)
    rescue
      nil
    end

    def self.describe(filed, candidates, today)
      line = "PLASTIC: filed #{filed} prior day ledger(s) into #{today}"
      remaining = candidates.size - filed
      remaining.positive? ? "#{line}, #{remaining} more wait for the next boot" : line
    end

    def self.run_candidates(store_dir, today)
      job = Job.new(filer: File.expand_path("../../file-session-intent", __dir__),
        templates: File.expand_path("../../../templates", __dir__), store_dir: store_dir, today: today)
      candidates = sweepable_days(job)
      [sweep_up_to_three(candidates, job), candidates]
    end

    def self.sweepable_days(job)
      sweep_root = SessionLedger.sessions_root(job.store_dir)
      return [] unless Dir.exist?(sweep_root) && File.exist?(job.filer)

      Dir.children(sweep_root).select { |name| sweepable_day?(sweep_root, name, job) }.sort
    end

    def self.sweepable_day?(sweep_root, name, job)
      File.directory?(File.join(sweep_root, name)) && SessionLedger.valid_day_id?(name) &&
        name < job.today && !SessionBackfill.closed?(job.store_dir, name)
    end

    def self.sweep_up_to_three(candidates, job)
      budget_end = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
      candidates.first(3).count { |day| within_budget?(budget_end) && sweep_one_day(job, day) }
    end

    def self.within_budget?(budget_end)
      Process.clock_gettime(Process::CLOCK_MONOTONIC) <= budget_end
    end

    def self.sweep_one_day(job, day)
      Timeout.timeout(5) { run_filer(job, day) }
    rescue
      false
    end

    def self.run_filer(job, day)
      store_dir = job.store_dir
      _out, _err, status = Open3.capture3({ "RUBYOPT" => nil }, RbConfig.ruby, job.filer,
        "--day", day, "--carry-to", job.today, "--store", store_dir, "--templates", job.templates)
      status.success? && SessionBackfill.closed?(store_dir, day)
    end
  end
end
