# frozen_string_literal: true

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
        @databases.fetch(:knowledge).transaction do |batch|
          batch.put(:rulings, ruling.to_h.except(:origin_id), statement: :insert)
          batch.put(:links, link_row(ruling, target), statement: :insert) if target
        end
        @retrieval.rulings(ruling.intent_id).find { |row| row.id == ruling.id }
      end

      def link_row(ruling, target) = { from_ref: ruling.ref, to_ref: target.ref, kind: "supersedes", at: ruling.at }

      def next_id(intent_id)
        highest = @retrieval.rulings(intent_id).filter_map { |ruling| ruling.id[/\AD(\d+)\z/, 1]&.to_i }.max || 0
        "D#{highest + 1}"
      end
    end
  end
end
