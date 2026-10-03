# frozen_string_literal: true

module Plastic
  module Graph
    module EvidenceText
      # Collapses whitespace while retaining the source line of each character.
      class NormalizedText
        def initialize(fragments) = @fragments = fragments

        def build
          state = State.new
          @fragments.each { |fragment| state.append(fragment) }
          state.extraction
        end

        # Holds the mutable normalized text state for a single extraction.
        class State
          def initialize
            @body = String.new
            @lines = []
            @space = nil
          end

          def append(fragment)
            character, line = fragment
            return @space ||= line if character.match?(/\s/)

            append_space
            @body << character
            @lines << line
            @space = nil
          end

          def extraction = Extraction.new(@body, @lines)

          private

          def append_space
            return unless @space && !@body.empty?

            @body << " "
            @lines << @space
          end
        end
      end
    end
  end
end
