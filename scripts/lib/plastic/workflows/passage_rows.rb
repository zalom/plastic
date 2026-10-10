# frozen_string_literal: true

module Plastic
  module Workflows
    # Presents search hits as ranked passages: the rank, the passage and the URI come first, and
    # the full body and the raw scores stay behind.
    class PassageRows
      KEPT = %w[uri store intent_id path position archived].freeze

      def initialize(passage_of: ->(row) { row.fetch("body") })
        @passage_of = passage_of
      end

      def call(rows) = rows.each_with_index.map { |row, index| present(row, index + 1) }

      private

      def present(row, rank) = { "rank" => rank, "passage" => @passage_of.call(row) }.merge(row.slice(*KEPT))
    end
  end
end
