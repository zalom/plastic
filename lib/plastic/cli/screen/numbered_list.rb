# frozen_string_literal: true

require_relative "outcomes"
require_relative "answer"

module Plastic
  class CLI
    class Screen
      # The list as numbered rows, the answer grammar, and a next: line that
      # sends the agent to the person. The next: command carries a
      # placeholder, so it cannot run as it stands and pick for the person.
      class NumberedList
        PLACEHOLDER = "<answer>"
        BECAUSE = "the person picks, not the agent; ask the person, then run the command again with their answer"

        def initialize(output)
          @output = output
        end

        # The rows of the list: the question, one numbered line per choice, and the answer grammar.
        def self.rows(question, choices)
          numbered = choices.each.with_index(1).map { |choice, number| choice.numbered(number) }
          { "question:" => question, "choices:" => numbered, "answer:" => Answer::GRAMMAR }
        end

        def call(question, choices, command:)
          self.class.rows(question, choices).each { |label, value| @output.row(label, value) }
          @output.next_step("#{command} #{PLACEHOLDER}", because: BECAUSE)
          Listed.new
        end
      end
    end
  end
end
