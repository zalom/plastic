# frozen_string_literal: true

module Plastic
  class CLI
    # How a call asks the person one question. The person is there only when
    # the input stream is a terminal and the answer is text, so a pipe, an
    # agent's call and `--json` never wait for a reply.
    class Dialog
      ASKS = 2

      attr_reader :output

      def initialize(input:, output:)
        @input = input
        @output = output
      end

      def terminal? = !@output.json? && @input.respond_to?(:tty?) && @input.tty?

      # The first answer that is one of `choices`, lowercased. The question
      # is asked again once on an answer it does not know, and nil comes back
      # when neither answer is one of them.
      def choose(question, choices:)
        ASKS.times do
          @output.raw(question)
          answer = @input.gets.to_s.strip.downcase
          return answer if choices.include?(answer)
        end
        nil
      end
    end
  end
end
