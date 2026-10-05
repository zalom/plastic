# frozen_string_literal: true

require "json"

module TestTimings
  CAPS = { file: 5.0, document: 10.0 }.freeze

  # Reads the timings file the Tests step wrote and fails a file or document
  # over its cap, naming it with its seconds. A file over its cap once is
  # re-run alone through `rerun` before it fails, so a slow file under
  # outside load is not called red on one bad run.
  class Caps
    # Raised for a missing timings file, or a file (or document) still over
    # its cap after being re-run alone.
    Failure = Class.new(StandardError)

    def self.cap_for(file) = file.start_with?("varar/") ? CAPS.fetch(:document) : CAPS.fetch(:file)

    def initialize(path, rerun:, out: $stdout)
      @path = path
      @rerun = rerun
      @out = out
    end

    def check
      raise Failure, "missing timings file: #{@path}" unless File.exist?(@path)

      JSON.parse(File.read(@path)).each { |file, seconds| check_one(file, seconds) }
    end

    private

    def check_one(file, seconds)
      cap = self.class.cap_for(file)
      return if seconds <= cap

      verify_rerun(file, seconds, cap)
    end

    def verify_rerun(file, seconds, cap)
      rerun_seconds = @rerun.call(file)
      @out.puts format("%s took %.1fs, re-run took %.1fs", file, seconds, rerun_seconds)
      return if rerun_seconds <= cap

      raise Failure, "#{file} took #{format("%.1f", seconds)}s, over its #{cap.to_i}s cap (re-run #{format("%.1f", rerun_seconds)}s)"
    end
  end
end
