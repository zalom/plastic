# frozen_string_literal: true

require "shellwords"

module Plastic
  class CLI
    # What one call answers: rows of label and value, the raw lines a JSON
    # answer carries, and the next: command with the because: line that
    # gives the rule behind it.
    class Result
      # The commands whose next: line keeps --project when the call named one.
      SCOPED = /\Aplastic (?:intent|auto|roadmap|continue|next|search|query|graph|node|edge|doctor|sync)\b/

      attr_reader :rows, :because

      def initialize
        @rows = []
        @lines = []
        @next_step = nil
        @because = nil
      end

      def row(label, value) = @rows << [label, value]

      def line(text) = @lines << text

      def offer(command, because)
        @next_step = command
        @because = because
      end

      # The next: command. A scoped command gets --project when the call
      # named a project and the command names none.
      def next_command(project)
        step = @next_step
        return step unless project && step&.match?(SCOPED) && !step.include?("--project")

        "#{step} --project #{Shellwords.escape(project)}"
      end

      # The last two lines of a text answer, or none when no next step is set.
      def closing_lines(project)
        @next_step ? ["next: #{next_command(project)}", "because: #{because}"] : []
      end

      # The JSON answer, with the same three parts and stable keys.
      def document(project)
        result = @rows.to_h
        result["output"] = @lines unless @lines.empty?
        {"result" => result, "next" => next_command(project), "because" => because}
      end
    end
  end
end
