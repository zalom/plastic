# frozen_string_literal: true

require_relative "document_get"

module Plastic
  module Commands
    # Fetches requested qualified documents in the exact request order.
    class DocumentBatch < DocumentGet
      argument :references, label: "REF", text: "one or more plastic://STORE/INTENT/PATH?revision=SHA256 references", rest: true
      reads :knowledge

      def call
        output.row("documents", parsed.fetch(:references).split.map { |reference| fetch(reference) })
        output.next_step("none", because: "the documents were read")
      end
    end
  end
end
