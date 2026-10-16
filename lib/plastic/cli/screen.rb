# frozen_string_literal: true

require_relative "screen/outcomes"
require_relative "screen/answer"
require_relative "screen/numbered_list"
require_relative "screen/terminal_list"

module Plastic
  class CLI
    # How a call asks the person to pick from a list. With a terminal on
    # both streams the person toggles the list there. With no terminal, or
    # with `--json`, the call prints the numbered list and stops, and the
    # next call reads the person's answer with Screen::Answer.
    class Screen
      def self.for(environment, output:) = new(input: environment.input, stream: environment.out, output:)

      def self.person_at?(io)
        io.tty?
      rescue NoMethodError
        false
      end

      def initialize(input:, stream:, output:, prompt: TerminalList.method(:prompt))
        @input = input
        @stream = stream
        @output = output
        @prompt = prompt
      end

      def terminal? = !@output.json? && [@input, @stream].all? { |io| self.class.person_at?(io) }

      # Chosen or Left from the terminal list; Listed once the numbered list
      # and its next: line are printed for `command`.
      def ask(question, choices, command:)
        return NumberedList.new(@output).call(question, choices, command:) unless terminal?

        TerminalList.new(@prompt.call(@input, @stream)).call(question, choices)
      end

      # The answer text that picks what the person picked on the terminal; nil
      # once the numbered list is printed for the next call to answer.
      def answer(question, choices, command:)
        result = ask(question, choices, command:)
        Answer.of(result, choices) unless result.is_a?(Listed)
      end
    end
  end
end
