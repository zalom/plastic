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
        output.row("document", fetch(parsed.fetch(:reference)))
        output.next_step("none", because: "the document was read")
      end

      private

      def fetch(reference) = retrieval_for(reference).fetch_reference(reference)

      def retrieval_for(reference)
        slug = reference[/\Aplastic:\/\/([^\/]+)/, 1]
        raise CLI::Scope::UnknownProject, "invalid document reference #{reference.inspect}" unless slug
        raise CLI::Scope::UnknownProject, "no project named #{slug.inspect}" unless scope.known_slugs.include?(slug)

        Graph.open(home: scope.plastic_home, store: slug).retrieval
      end
    end
  end
end
