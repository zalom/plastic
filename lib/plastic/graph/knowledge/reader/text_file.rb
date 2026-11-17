# frozen_string_literal: true

require_relative "../../retrieval/evidence/document"
require_relative "../../retrieval/evidence/rows"
require_relative "../../retrieval/evidence/removal"

module Plastic
  module Graph
    module Knowledge
      class Reader
        # A text file of an intent folder read into the rows of its document, or of a legacy row.
        class TextFile
          # The text of one file of an intent and the time it is read at.
          Subject = Data.define(:intent_id, :rel, :text, :now) do
            def document = Retrieval::Evidence::Document.new(intent_id, rel, text, now:)

            def legacy_row = { intent_id:, path: rel, body: text, updated_at: now }

            def removed_by(removal) = removal.remove(intent_id, rel)
          end

          def initialize(subject, origin_id)
            @subject = subject
            @origin_id = origin_id
          end

          def document(batch) = Retrieval::Evidence::Rows.new(batch, @subject.document, @origin_id).write

          # The row replaces the document, head and search rows the path held before it was legacy.
          def legacy(batch)
            batch.put(:legacy_intents_data, @subject.legacy_row)
            @subject.removed_by(Retrieval::Evidence::Removal.new(batch, @origin_id))
          end
        end
      end
    end
  end
end
