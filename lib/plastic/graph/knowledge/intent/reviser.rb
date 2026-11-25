# frozen_string_literal: true

require_relative "reviser/change"
require_relative "../../evidence/writer"

module Plastic
  module Graph
    module Knowledge
      class Intent
        # Rewrites an intent's What and Why: the text of its own file in the
        # knowledge graph, then its title row. The work log line of the revise
        # holds the old What and Why.
        class Reviser
          TITLE_SQL = <<~SQL
            UPDATE intents SET title = :title, updated_at = :now
            WHERE intent_id = :intent_id AND origin_id = :origin AND status NOT IN ('done', 'abandoned')
          SQL

          def initialize(databases, retrieval, clock:)
            @databases = databases
            @retrieval = retrieval
            @clock = clock
          end

          # The change, or nil when the intent has no file row.
          def change(intent, line, why)
            key = key_of(intent)
            document = @retrieval.fetch(*key)
            document && Change.new(intent:, document:, line:, why:)
          end

          # Writes the change and returns the qualified reference of the new text.
          def write(change)
            key = key_of(change.intent)
            Retrieval::Evidence::Writer.new(@databases.fetch(:store), @retrieval.origin_id, clock: @clock).write(*key, change.body)
            write_title(key.first, change.line)
            uri(key)
          end

          private

          def key_of(intent) = intent.key_among(paths_of(intent))

          def paths_of(intent) = @retrieval.documents(intent.intent_id).map(&:path)

          def uri(key) = @retrieval.reference(*key).fetch(:uri)

          def write_title(intent_id, title)
            @databases.fetch(:store).transaction do |batch|
              batch.write(:intents, TITLE_SQL, title:, intent_id:, origin: @retrieval.origin_id, now: Plastic.timestamp(@clock.now))
            end
          end
        end
      end
    end
  end
end
