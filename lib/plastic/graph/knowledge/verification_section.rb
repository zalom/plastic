# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      # The Verification section of a markdown document: the lines under the heading of that name, of any
      # level, up to the next heading of the same or a higher level. No document means no lines.
      class VerificationSection
        HEADING = /\A(#+)\s*(.*?)\s*\z/
        BULLET = /\A[-*]\s*(?:\[[ xX]\]\s*)?(.+)\z/

        def initialize(body)
          @lines = body.to_s.lines.map(&:chomp)
          @headings = @lines.map { |line| line.match(HEADING) }
        end

        # The bullets of the section, without dash, checkbox and bold marks.
        def bullets = lines.filter_map { |line| line[BULLET, 1]&.delete("*")&.strip }

        private

        def lines
          start = @headings.index { |found| found && found[2].casecmp?("Verification") }
          return [] unless start

          @lines[(start + 1)...section_end(start)]
        end

        def section_end(start)
          depth = @headings[start][1].size
          later = @headings.each_with_index.drop(start + 1)
          later.find { |found, _index| found && found[1].size <= depth }&.last || @lines.size
        end
      end
    end
  end
end
