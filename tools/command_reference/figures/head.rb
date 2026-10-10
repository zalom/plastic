# frozen_string_literal: true

module CommandReference
  module Figures
    WINGS = {
      down: [[-5, -8], [0, 0], [5, -8]], left: [[8, -5], [0, 0], [8, 5]], right: [[-8, -5], [0, 0], [-8, 5]]
    }.freeze
    DIRECTIONS = { 0 => :down, 1 => :left, -1 => :right }.freeze

    # The arrow tip at the end of a wire, pointing the way the last leg runs.
    Head = Data.define(:tip, :from) do
      def markup = %(<path d="M #{corners.join(" L ")} Z" class="head"/>)

      private

      def corners = WINGS.fetch(DIRECTIONS.fetch(from.left <=> tip.left)).map { |across, down| tip.shift(across, down) }
    end
  end
end
