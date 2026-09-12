# encoding: UTF-8
# frozen_string_literal: true

require "minitest"

# FailuresReporter (intent 355, n4, D5): a Minitest reporter that prints only
# what a named run needs back - each failure with its file, line and message,
# then the summary line - never a dot per test and never the "Run options" /
# "# Running:" preamble. A green run costs one line; a red run costs the
# failures plus that line. The executor's context never carries thousands of
# dots for one edit.
class FailuresReporter < Minitest::StatisticsReporter
  def report
    super
    results.reject(&:skipped?).each { |result| io.puts result.to_s }
    io.puts summary
  end

  def summary
    format("%d runs, %d assertions, %d failures, %d errors, %d skips",
           count, assertions, failures, errors, skips)
  end
end

module Minitest
  # Replaces the default CompositeReporter's SummaryReporter and
  # ProgressReporter with FailuresReporter, the same plugin seam Minitest's
  # own StatisticsReporter docs point to for swapping its output.
  def self.plugin_failures_reporter_init(options)
    reporter.reporters.reject! { |r| r.is_a?(SummaryReporter) || r.is_a?(ProgressReporter) }
    reporter << FailuresReporter.new(options[:io], options)
  end
end

Minitest.register_plugin("failures_reporter") unless Minitest.extensions.include?("failures_reporter")
