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
        target = supersedes && find_ruling(intent_id, supersedes.delete_prefix("#{intent_id}/"))
        return nil if supersedes && !target

        ruling = Ruling.new(intent_id:, id: next_id(intent_id), text:, supersedes: target&.id, at: Plastic.now, session_id: @session, origin_id: nil)
        write_rows(rulings: ruling.to_h.except(:origin_id), links: target && Link.supersedes(ruling, target))
        find_ruling(intent_id, ruling.id)
      end

      private

      def find_ruling(intent_id, id) = @retrieval.rulings(intent_id).find { |ruling| ruling.id == id }

      def write_rows(rows)
        @databases.fetch(:knowledge).transaction { |batch| batch.insert_rows(rows.compact) }
      end

      def next_id(intent_id) = NextId.after(@retrieval.rulings(intent_id), prefix: "D")
    end
  end
end
