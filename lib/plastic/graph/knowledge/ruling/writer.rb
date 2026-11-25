# frozen_string_literal: true

require_relative "../ruling"
require_relative "../link"
require_relative "../../next_id"

module Plastic
  module Graph
    module Knowledge
      class Ruling
        # Writes one intent's rulings: the next D id, and the `supersedes` link
        # when the call names an older ruling. A text that begins with a label of
        # its own id, such as "D3: Ship it", is stored without it.
        class Writer
          # A label of `id`: copies of the id with spaces between, then a colon, a period before a space or any dash,
          # or a space before a capital letter, a backtick, a quote or a bracket. A list sign or another id after it,
          # or a range word, which is lowercase, leaves the text alone, such as "D1 through D8 are binding".
          def self.label(id)
            own = Regexp.escape(id)
            /\A(?:#{own}\s+)*#{own}(?:\s*(?::|\.(?=\s)|[-–—])\s*|\s+(?=[A-Z`"'(\[]))(?=\S)(?![-–—.:,\/])(?!(?!#{own}\b)D\d)/
          end

          # The text without its leading labels of `id`.
          def self.own_text(text, id)
            stripped = text.sub(label(id), "")
            (stripped == text) ? text : own_text(stripped, id)
          end

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
