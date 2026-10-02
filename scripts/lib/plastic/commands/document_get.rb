# frozen_string_literal: true

require_relative "../cli/command"
require_relative "../graph"

module Plastic
  module Commands
    # Fetches one current or immutable document by its qualified reference.
    class DocumentGet < CLI::Command
      argument :reference, label: "REF", text: "the qualified document reference"
      reads :knowledge

      def call
        output.row("document", retrieval.fetch_reference(parsed.fetch(:reference)))
        output.next_step("none", because: "the document was read")
      end

      private

      def retrieval = graphs.retrieval
    end
  end
end
