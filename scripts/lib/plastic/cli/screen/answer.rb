# frozen_string_literal: true

require_relative "outcomes"
require_relative "../command/usage"

module Plastic
  class CLI
    class Screen
      # The person's answer to a numbered list, read against its choices.
      class Answer
        GRAMMAR = "answer with numbers separated by commas (1,2), a for all, or q to leave with no change"
        ALL = "a"
        LEAVE = "q"
        NUMBERS = /\A\d+(?:\s*,\s*\d+)*\z/

        # The numbers of an answer such as `1, 2`; anything else is a usage error that says the grammar.
        def self.numbers(answer)
          raise Command::Usage, "unknown answer #{answer.inspect}; #{GRAMMAR}" unless answer.match?(NUMBERS)

          answer.split(",").map(&:to_i)
        end

        def initialize(choices)
          @labels = choices.map(&:label)
        end

        def call(text)
          answer = text.to_s.strip
          case answer.downcase
          when ALL then Chosen.new(labels: @labels)
          when LEAVE then Left.new
          else Chosen.new(labels: picked(self.class.numbers(answer)))
          end
        end

        private

        def picked(numbers)
          unknown = numbers.find { |number| number.zero? || number > @labels.size }
          raise Command::Usage, "no choice #{unknown}; the choices are #{valid}" if unknown

          @labels.select.with_index(1) { |_label, number| numbers.include?(number) }
        end

        def valid = (1..@labels.size).to_a.join(", ")
      end
    end
  end
end
