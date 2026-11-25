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

        def to_a = @lines.slice_before { |line| line.match?(BULLET) }.filter_map { |group| self.class.joined(*group) }

        # The text of a bullet line joined with the indented lines that wrap it, or nil when `head` is no bullet.
        def self.joined(head, *rest)
          text = head[BULLET, 1]
          return unless text

          [text, *rest.take_while { |line| line.match?(WRAPPED) }.map(&:strip)].join(" ")
        end
      end
    end
  end
end
