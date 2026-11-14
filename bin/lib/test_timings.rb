# frozen_string_literal: true

require "json"
require "fileutils"
require "minitest"
require "benchmark"
require "open3"
require_relative "test_timings/documents"
require_relative "test_timings/caps"

# The gate's timing check: a Minitest extension that sums
# each test's time per file, and the cap check a gate step runs on what it
# wrote. Registered through Minitest's own extension list, the same seam
# FailuresReporter uses, and active only when PLASTIC_TEST_TIMINGS names a
# file to write. With no file named, `plugin_test_timings_init` returns at
# once: no reporter is added, so a mutant child pays nothing for this file
# being loaded.
module TestTimings
  # The Minitest reporter: one line of JSON, file (or document) to seconds.
  class Reporter < Minitest::AbstractReporter
    def initialize(path, documents: Documents.new)
      super()
      @path = path
      @documents = documents
      @totals = Hash.new(0.0)
    end

    def record(result)
      @totals[@documents.book(result)] += result.time
    end

    def report
      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, JSON.generate(@totals))
    end
  end
end

Minitest.extensions << "test_timings" unless Minitest.extensions.include?("test_timings")

# Reopened only to add `plugin_test_timings_init`, the hook Minitest calls
# for every name in `Minitest.extensions`, the same seam FailuresReporter
# uses to add itself.
module Minitest
  def self.plugin_test_timings_init(_options, env: ENV, composite: reporter)
    return unless (path = env.fetch("PLASTIC_TEST_TIMINGS", nil))

    composite << TestTimings::Reporter.new(path)
  end
end

module TestTimings
  # Re-runs one file or Varar document alone, through the same `bin/test` a
  # contributor would use, so a cap failure times a real second run instead
  # of trusting the first. Minitest's class filter selects the named Varar
  # document while the adapter loads the project for reference resolution.
  class Rerun
    def initialize(root: File.expand_path("../..", __dir__), runner: ->(*command, chdir:) { Open3.capture2e(*command, chdir:) })
      @root = root
      @runner = runner
    end

    def call(file)
      Benchmark.realtime do
        output, status = @runner.call(*command(file), chdir: @root)
        raise Caps::NotRun, "#{file} rerun failed: #{output}" unless status.success?
      end
    end

    private

    def command(file)
      return ["bundle", "exec", "ruby", "bin/test", "--only", file] unless file.start_with?("varar/")

      require "varar/minitest"
      name = Regexp.escape("Var_#{Varar::Minitest.identifier(file)}")
      ["bundle", "exec", "ruby", "bin/test", "--name", "/\\A#{name}#/", "--system"]
    end
  end

  # The exit status of the cap check: 0 when every file is under its cap, 1 when a cap is
  # missed, 3 when the check could not run.
  def self.verdict(path, rerun: Rerun.new, err: $stderr)
    Caps.new(path, rerun:).check
    0
  rescue Caps::NotRun => e
    err.puts e.message
    3
  rescue Caps::Failure => e
    err.puts e.message
    1
  end

  # The command line: `check PATH`; any other call prints the usage and exits 2.
  def self.cli(argv, rerun: nil, err: $stderr)
    command, path = argv
    return verdict(path, **{ rerun:, err: }.compact) if command == "check" && path

    err.puts "Usage: bin/lib/test_timings.rb check PATH"
    2
  end
end

exit TestTimings.cli(ARGV) if $PROGRAM_NAME == __FILE__
