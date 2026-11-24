# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      # The bullets of a run of outcome.md lines. A bullet is joined with the indented lines that wrap it, so a long
      # delivery line reads whole; an indented line that starts with its own marker is a sub-bullet and is left out.
      class OutcomeBullets
        BULLET = /\A[-*]\s*(?:\[[ xX]\]\s*)?(.+)\z/
        WRAPPED = /\A\s+(?![-*]\s)\S/

        def initialize(lines)
          @lines = lines
        end

        def to_a = @lines.slice_before { |line| line.match?(BULLET) }.filter_map { |group| joined(group) }

        private

        def joined(group)
          text = group.first[BULLET, 1]
          return unless text

          [text, *group.drop(1).take_while { |line| line.match?(WRAPPED) }.map(&:strip)].join(" ")
        end
      end
    end
  end
end
