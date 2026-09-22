# frozen_string_literal: true

require "json"
require "shellwords"

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

      attr_writer :project

      def initialize(out:, err:, json: false)
        @json = json
        @raw = []
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

      def document(value)
        @out.puts JSON.pretty_generate(value)
        @flushed = true
        self
      end

      def raw(text)
        @json ? @raw << text : @out.puts(text)
        self
      end

      def usage(message, banner)
        @err.puts "plastic: #{message}"
        @err.puts banner
        error_document(message, "usage")
        self
      end

      def refused(message)
        @err.puts "plastic: refused, #{message}"
        @err.puts "This step belongs to the owner. Stop and ask; do not retry with a flag."
        error_document(message, "refused")
        self
      end

      def failed(message)
        @err.puts "plastic: #{message}"
        error_document(message, "failed")
        self
      end

      private

      def error_document(message, kind)
        return unless @json

        row("error", {"kind" => kind, "message" => message})
        next_step("none", because: message)
        flush(json: true)
      end

      def result
        data = @rows.to_h
        data["output"] = @raw unless @raw.empty?
        data
      end

      def scoped_next
        return @next_step unless @project && @next_step&.match?(/\Aplastic (?:intent|auto|roadmap|continue|next|search)\b/)
        return @next_step if @next_step.include?("--project")

        "#{@next_step} --project #{Shellwords.escape(@project)}"
      end

      def print_json
        @out.puts JSON.pretty_generate("result" => result, "next" => scoped_next,
          "because" => @because)
      end

      def print_text
        printed = print_rows
        return unless @next_step

        @out.puts if printed
        @out.puts "next: #{scoped_next}"
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
