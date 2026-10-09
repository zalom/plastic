# frozen_string_literal: true

require "json"
require_relative "offer"
require_relative "result"

module Plastic
  class CLI
    # One place where a command's answer is printed. A result is rows of label
    # and value; every command ends with a `next:` line and the `because:` line
    # that gives the rule behind it. TextOutput prints them as lines and
    # JsonOutput, for `--json`, as one document with stable keys. Results go
    # to the output stream and diagnostics to the error stream, so a caller
    # can pipe one without the other. Nothing here colors its output.
    class Output
      def initialize(out:, err:)
        @out = out
        @err = err
        @result = Result.new
        @flushed = false
      end

      def json? = false

      def flushed? = @flushed

      def flush_rows(_project = nil) = self

      def row(label, value) = tap { @result.row(label, value) }

      def rows(entries) = tap { entries.each { |label, value| row(label, value) } }

      def next_step(command, because:) = tap { @result.offer(command, because) }

      # Prints the answer once. `project` is the store the call named, so a
      # scoped next: command keeps it.
      def flush(project = nil)
        return self if @flushed

        @flushed = true
        print_answer(project)
        self
      end

      def document(value)
        @out.puts JSON.pretty_generate(value)
        @flushed = true
        self
      end

      def usage(message, banner)
        diagnose("plastic: #{message}", banner)
        error_document(message, "usage", Offer.none(message))
      end

      def refused(message, offer = Offer.none(message))
        diagnose("plastic: refused, #{message}", "This step belongs to the owner. Stop and ask; do not retry with a flag.")
        error_document(message, "refused", offer)
      end

      def failed(message, offer = Offer.none(message), source: nil)
        diagnose("plastic: #{message}")
        error_document(source ? "#{source}: #{message}" : message, "failed", offer)
      end

      private

      attr_reader :out, :result

      def diagnose(*lines) = @err.puts(*lines)

      def error_document(_message, _kind, offer) = offer.apply(self)
    end
  end
end
