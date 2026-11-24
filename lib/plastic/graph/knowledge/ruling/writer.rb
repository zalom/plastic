# frozen_string_literal: true

require_relative "../ruling"
require_relative "../link"
require_relative "../../next_id"

module Plastic
  module Graph
    module Knowledge
      class Ruling
        # Writes one intent's rulings: the next D id, and the `supersedes` link
        # when the call names an older ruling. A text that begins with a copy of
        # its own id, such as "D3: Ship it", is stored without it.
        class Writer
          # The text without the leading copies of `id`, each with the space, colon, period or dash after it.
          def self.own_text(text, id) = text.sub(/\A(?:#{Regexp.escape(id)}\b[\s:.-]+(?=\S))+/, "")

          def initialize(databases, retrieval, clock:, session: nil)
            @databases = databases
            @retrieval = retrieval
            @session = session
            @clock = clock
          end

          # Returns the new ruling, or nil when `supersedes` names no ruling.
          def add_ruling(intent_id:, text:, supersedes: nil)
            target = supersedes && find_ruling(intent_id, supersedes.delete_prefix("#{intent_id}/"))
            return nil if supersedes && !target

            id = next_id(intent_id)
            ruling = Ruling.new(intent_id:, id:, text: Writer.own_text(text, id), supersedes: target&.id, at: Plastic.timestamp(@clock.now), session_id: @session,
              origin_id: nil)
            write_rows(rulings: ruling.to_h.except(:origin_id), links: target && Link.supersedes(ruling, target))
            find_ruling(intent_id, ruling.id)
          end

          private

          def find_ruling(intent_id, id) = @retrieval.rulings(intent_id).find { |ruling| ruling.id == id }

          def write_rows(rows)
            @databases.fetch(:store).transaction { |batch| batch.insert_rows(rows.compact) }
          end

          def next_id(intent_id) = NextId.after(@retrieval.rulings(intent_id), prefix: "D")
        end
      end
    end
  end
end
