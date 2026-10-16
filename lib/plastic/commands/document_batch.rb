# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Fetches requested qualified documents in the exact request order.
    class DocumentBatch < Routine
      argument :references, label: "REF", text: "one or more plastic://STORE/INTENT/PATH?revision=SHA256 references", rest: true
      reads :knowledge

      workflow :code_batch_documents, next: :noop
    end
  end
end
