# frozen_string_literal: true

require_relative "../intent"

require_relative "../../evidence/writer"

module Plastic
  module Graph
    module Knowledge
      class Intent
        # Writes the whole text of one document of an intent as its new revision, the earlier text kept as an
        # earlier revision, and answers the document's reference.
        class DocumentWriter
          def initialize(databases, retrieval)
            @databases = databases
            @retrieval = retrieval
          end

          def write(intent_id, file, body)
            Retrieval::Evidence::Writer.new(@databases.fetch(:store), @retrieval.origin_id, clock: @retrieval.clock).write(intent_id, file, body)
            @retrieval.reference(intent_id, file).fetch(:uri)
          end
        end
      end
    end
  end
end
