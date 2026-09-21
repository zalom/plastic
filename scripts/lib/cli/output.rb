# frozen_string_literal: true

require "json"

# Plastic::CLI::Output (intent 363) - one place where a command's answer is
# printed. A result is rows of label and value; every command ends with a
# `next:` line and the `because:` line that gives the rule behind it, which is
# where the step order the skills used to carry now lives. `--json` prints the
# same three things with stable keys.
#
# Results go to the output stream and diagnostics to the error stream, so a
# caller can pipe one without the other. Nothing here colours its output.
module Plastic
  class CLI
    class Output
      LABEL_GAP = 2

      def initialize(out:, err:)
        @out = out
        @err = err
        @rows = []
        @next_step = nil
        @because = nil
        @flushed = false
      end

      def row(label, value)
        @rows << [label, value]
        self
      end

      def next_step(command, because:)
        @next_step = command
        @because = because
        self
      end

      def flush(json: false)
        return self if @flushed

        @flushed = true
        json ? print_json : print_text
        self
      end

      def usage(message, banner)
        @err.puts "plastic: #{message}"
        @err.puts banner
        self
      end

      def refused(message)
        @err.puts "plastic: refused, #{message}"
        @err.puts "This step belongs to the owner. Stop and ask; do not retry with a flag."
        self
      end

      def failed(message)
        @err.puts "plastic: #{message}"
        self
      end

      private

      def print_json
        @out.puts JSON.pretty_generate("result" => @rows.to_h, "next" => @next_step,
          "because" => @because)
      end

      def print_text
        printed = print_rows
        return unless @next_step

        @out.puts if printed
        @out.puts "next: #{@next_step}"
        @out.puts "because: #{@because}"
      end

      def print_rows
        width = label_width
        printed = false
        @rows.each do |label, value|
          Array(value).each_with_index do |item, index|
            @out.puts "#{(index.zero? ? label : "").ljust(width)}#{item}"
            printed = true
          end
        end
        printed
      end

      def label_width
        widths = @rows.reject { |_label, value| Array(value).empty? }.map { |label, _value| label.length }
        widths.empty? ? 0 : widths.max + LABEL_GAP
      end
    end
  end
end
