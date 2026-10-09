# frozen_string_literal: true

require "json"
require_relative "result"

module Plastic
  class CLI
    # One place where a command's answer is printed. A result is rows of label
    # and value; every command ends with a `next:` line and the `because:` line
    # that gives the rule behind it. TextOutput prints them as lines and
    # JsonOutput, for `--json`, as one document with stable keys. Results go
    # to the output stream and diagnostics to the error stream, so a caller
    # can pipe one without the other. Nothing here colors its output. The
    # report shape is in docs/reference/report.md.
    class Output
      def initialize(out:, err:)
        @out = out
        @err = err
        @result = Result.new
        @flushed = false
      end

      def json? = false

      def flush_rows(_project = nil) = self

      def row(label, value) = tap { @result.row(label, value) }

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
        @err.puts "plastic: #{message}", banner
        error_document(message, "usage", nil, message)
      end

      def refused(message, next_command: nil, because: message)
        @err.puts "plastic: refused, #{message}", "This step belongs to the owner. Stop and ask; do not retry with a flag."
        error_document(message, "refused", next_command, because)
      end

      def failed(message, next_command: nil, because: message)
        @err.puts "plastic: #{message}"
        error_document(message, "failed", next_command, because)
      end

      private

      attr_reader :out, :result

      # A text answer says nothing more on an error; the error line is enough.
      def error_document(_message, _kind, next_command, because) = next_command ? next_step(next_command, because:) : self
    end
  end
end
