# frozen_string_literal: true

require_relative "../cli/command"

module Plastic
  module Commands
    # Fetches requested qualified documents in the exact request order.
    class DocumentBatch < CLI::Command
      argument :references, label: "REF", text: "one or more qualified document references", rest: true
      reads :knowledge

      def call
        output.row("documents", graphs.retrieval.fetch_batch(parsed.fetch(:references).split))
        output.next_step("none", because: "the documents were read")
      end
    end
  end
end
