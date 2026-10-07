# frozen_string_literal: true

require_relative "reviser/change"
require_relative "../store_folder"
require_relative "../../retrieval/evidence/writer"

module Plastic
  module Graph
    module Knowledge
      class Intent
        # Rewrites an intent's What and Why: a new revision of its own file in
        # the knowledge graph, then its title row. The old revision row stays,
        # so the old text reads back by its qualified reference.
        class Reviser
          TITLE_SQL = <<~SQL
            UPDATE intents SET title = :title, updated_at = :now
            WHERE intent_id = :intent_id AND origin_id = :origin AND status NOT IN ('done', 'abandoned')
          SQL

          def initialize(databases, retrieval, folder)
            @databases = databases
            @retrieval = retrieval
            @folder = folder
          end

          # The change, or nil when the intent has no file row.
          def change(intent, line, why)
            key = intent.document_key
            document = @retrieval.fetch(*key)
            document && Change.new(intent:, document:, history: uri(key), edited: edited(intent), line:, why:)
          end

          # Writes the change and returns the qualified references of the old and the new revision.
          def write(change)
            key = change.intent.document_key
            Retrieval::Evidence::Writer.new(@databases.fetch(:knowledge), @retrieval.origin_id).write(*key, change.body)
            write_title(key.first, change.line)
            [change.history, uri(key)]
          end

          private

          def uri(key) = @retrieval.reference(*key).fetch(:uri)

          def edited(intent)
            printed = @retrieval.printed
            ["#{intent.dir}/#{intent.file}", StoreFolder::INDEX].find { |path| @folder.exist?(path) && @folder.digest(path) != printed[path] }
          end

          def write_title(intent_id, title)
            @databases.fetch(:work).transaction do |batch|
              batch.write(:intents, TITLE_SQL, title:, intent_id:, origin: @retrieval.origin_id, now: Plastic.now)
            end
          end
        end
      end
    end
  end
end
