# frozen_string_literal: true

module Plastic
  module Graph
    module Retrieval
      class Search
        # Turns the words of a question into an FTS5 match expression. Each word is quoted, so no word works as FTS
        # syntax. The words are joined with OR and BM25 ranks the passage that holds more of them first. A quoted
        # phrase stays one phrase. Common words drop out, unless they are all the question holds.
        class Query
          PARTS = /"([^"]*)"|([\p{Alnum}_]+)/
          STOP_WORDS = %w[a an and are as at be by do does for from how i in is it my of on or that the this to was what when where which who why with].freeze

          def initialize(text)
            @parts = text.to_s.scan(PARTS)
          end

          def to_s = terms.uniq(&:downcase).map { |term| %("#{term}") }.join(" OR ")

          private

          def terms
            phrases = @parts.filter_map { |phrase, _word| words(phrase) if phrase }
            singles = @parts.filter_map { |_phrase, word| word }
            kept = singles.reject { |word| STOP_WORDS.include?(word.downcase) }
            kept = singles if kept.empty? && phrases.empty?
            [*phrases, *kept]
          end

          def words(phrase) = phrase.scan(/[\p{Alnum}_]+/).join(" ").then { |joined| joined unless joined.empty? }
        end
      end
    end
  end
end
