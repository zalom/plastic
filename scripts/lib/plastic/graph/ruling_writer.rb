# frozen_string_literal: true

require_relative "link"
require_relative "next_id"

module Plastic
  module Graph
    # Writes one intent's rulings: the next D id, and the `supersedes` link
    # when the call names an older ruling.
    class RulingWriter
      def initialize(databases, retrieval, session: nil)
        @databases = databases
        @retrieval = retrieval
        @session = session
      end

      # Returns the new ruling, or nil when `supersedes` names no ruling.
      def add_ruling(intent_id:, text:, supersedes: nil)
        target = find_target(intent_id, supersedes)
        return nil if supersedes && !target

        write(Ruling.new(intent_id:, id: next_id(intent_id), text:, supersedes: target&.id, at: Plastic.now,
          session_id: @session, origin_id: nil), target)
      end

      private

      def find_target(intent_id, supersedes)
        return nil unless supersedes

        id = supersedes.delete_prefix("#{intent_id}/")
        @retrieval.rulings(intent_id).find { |ruling| ruling.id == id }
      end

      def write(ruling, target)
        write_row(ruling, target)
        refetch(ruling)
      end

      def write_row(ruling, target)
        row = ruling.to_h.except(:origin_id)
        link = Link.supersedes(ruling, target) if target
        @databases.fetch(:knowledge).transaction do |batch|
          batch.put(:rulings, row, statement: :insert)
          batch.put(:links, link, statement: :insert) if target
        end
      end

      def refetch(ruling) = @retrieval.rulings(ruling.intent_id).find { |row| row.id == ruling.id }

      def next_id(intent_id) = NextId.after(@retrieval.rulings(intent_id), prefix: "D")
    end
  end
end
