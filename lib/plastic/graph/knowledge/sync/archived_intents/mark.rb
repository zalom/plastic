# frozen_string_literal: true

require_relative "../../intent"
require_relative "../../reader/index_file"

module Plastic
  module Graph
    module Knowledge
      class Sync
        class ArchivedIntents
          # One archive entry of the index with the index entry of its intent: the rows they stand for.
          Mark = Data.define(:fields, :entry) do
            def intent_id = fields["intent_id"]

            def intent_row = Intent.from_h(Reader::IndexFile.intent_row(entry)).new_row

            def archive_row = { intent_id:, at: fields["at"], restored_at: nil, session_id: fields["session_id"] }

            def completion_rows = [fields["completion"]].grep(Hash).map { |hash| Work::CompletionRow.stored(hash, intent_id) }

            def put_all(batch)
              batch.put(:intents, intent_row)
              batch.put(:archives, archive_row)
              completion_rows.each { |row| batch.put(:completions, row) }
            end
          end
        end
      end
    end
  end
end
