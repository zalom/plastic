# frozen_string_literal: true

require "json"
require "fileutils"
require "minitest"

# The gate's timing check: a Minitest extension that sums
# each test's time per file, and the cap check a gate step runs on what it
# wrote. Registered through Minitest's own extension list, the same seam
# FailuresReporter uses, and active only when PLASTIC_TEST_TIMINGS names a
# file to write. With no file named, `plugin_test_timings_init` returns at
# once: no reporter is added, so a mutant child pays nothing for this file
# being loaded.
module TestTimings
  CAPS = { file: 5.0, document: 10.0 }.freeze

  # Books a finished Minitest result to the file it ran from, or, when its
  # class is one a Varar document generated, to that document. Every class a
  # Varar document generates is defined inside the varar-minitest gem's own
  # file, so a result's method source location always points there and
  # never at the document; the document list, read from varar.config.json,
  # is what tells the two apart.
  class Documents
    CONFIG_FILE = "varar.config.json"

    def initialize(root: File.expand_path("../..", __dir__))
      @root = root
    end

    def book(result)
      class_names.fetch(result.klass) { file_of(result) }
    end

    private

    def class_names
      @class_names ||= documents.to_h { |path| [varar_class_name(path), path] }
    end

    def documents
      config_path = File.join(@root, CONFIG_FILE)
      return [] unless File.exist?(config_path)

      config = JSON.parse(File.read(config_path))
      Array(config.dig("docs", "include")).flat_map { |glob| Dir.glob(File.join(@root, glob)) }
        .map { |full| full.delete_prefix("#{@root}/") }.sort
    end

    def varar_class_name(path)
      require "varar/minitest"
      "Var_#{Varar::Minitest.identifier(path)}"
    end

    def file_of(result)
      Object.const_get(result.klass).instance_method(result.name).source_location.first.delete_prefix("#{@root}/")
    end
  end

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

  # Reads the timings file the Tests step wrote and fails a file or document
  # over its cap, naming it with its seconds. A file over its cap once is
  # re-run alone through `rerun` before it fails, so a slow file under
  # outside load is not called red on one bad run.
  class Caps
    Failure = Class.new(StandardError)

    def initialize(path, rerun:)
      @path = path
      @rerun = rerun
    end

    def check!
      raise Failure, "missing timings file: #{@path}" unless File.exist?(@path)

      JSON.parse(File.read(@path)).each { |file, seconds| check_one(file, seconds) }
    end

    private

    def check_one(file, seconds)
      cap = cap_for(file)
      return if seconds <= cap

      seconds = @rerun.call(file)
      return if seconds <= cap

      raise Failure, "#{file} took #{format("%.1f", seconds)}s, over its #{cap.to_i}s cap"
    end

    def cap_for(file) = file.start_with?("varar/") ? CAPS.fetch(:document) : CAPS.fetch(:file)
  end
end

Minitest.extensions << "test_timings" unless Minitest.extensions.include?("test_timings")

module Minitest
  def self.plugin_test_timings_init(options)
    path = ENV.fetch("PLASTIC_TEST_TIMINGS", nil)
    return unless path

    reporter << TestTimings::Reporter.new(path)
  end
end

module TestTimings
  # Re-runs one file or Varar document alone, through the same `bin/test` a
  # contributor would use, so a cap failure times a real second run instead
  # of trusting the first. A Varar document has no single-file entry point,
  # so it reruns the whole Varar suite and charges the document its time.
  class Rerun
    def initialize(root: File.expand_path("../..", __dir__))
      @root = root
    end

    def call(file)
      command = file.start_with?("varar/") ? %w[bundle exec ruby bin/test --system] : ["bundle", "exec", "ruby", "bin/test", "--only", file]
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      Open3.capture2e(*command, chdir: @root)
      Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
    end
  end
end

if $PROGRAM_NAME == __FILE__
  require "open3"

  command, path = ARGV
  unless command == "check" && path
    warn "Usage: bin/lib/test_timings.rb check PATH"
    exit 2
  end

  begin
    TestTimings::Caps.new(path, rerun: TestTimings::Rerun.new).check!
  rescue TestTimings::Caps::Failure => e
    warn e.message
    exit 1
  end
end
