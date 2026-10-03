# frozen_string_literal: true

module Plastic
  module Graph
    module EvidenceText
      # Collapses whitespace while retaining the source line of each character.
      class NormalizedText
        def initialize(fragments) = @fragments = fragments

        def build
          State.new.build(@fragments)
        end

        # Holds the mutable normalized text state for a single extraction.
        class State
          def initialize
            @body = String.new
            @lines = []
            @space = nil
          end

          def build(fragments)
            fragments.each { |fragment| append(fragment) }
            extraction
          end

          def append(fragment)
            character, line = fragment
            return remember_space(line) if character.match?(/\s/)

            append_character(character, line)
          end

          def extraction = Extraction.new(@body, @lines)

          private

          def remember_space(line) = @space ||= line

          def append_character(character, line)
            append_space
            @body << character
            @lines << line
            @space = nil
          end

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
