# frozen_string_literal: true

require_relative "../cli/command"
require_relative "../graph/retrieval_source"
require_relative "document_reference"

module Plastic
  module Commands
    # Fetches one current or immutable document by its qualified reference.
    class DocumentGet < CLI::Command
      argument :reference, label: "REF", text: "plastic://STORE/INTENT/PATH?revision=SHA256"
      option :passage, switch: "--passage N", text: "one-based bounded passage position"
      reads :knowledge

      def call
        output.row("document", selected(parsed.fetch(:reference)))
        output.next_step("none", because: "the document was read")
      rescue Graph::RetrievalGraph::MissingReference, Graph::RetrievalGraph::MaintenanceRequired, CLI::Scope::UnknownProject => error
        raise CLI::Command::Failure, error.message
      end

      private

      def fetch(reference)
        retrieval_for(reference).fetch_reference(reference)
      end

      def selected(reference)
        return fetch(reference) unless parsed[:passage]

        retrieval_for(reference).fetch_passage(reference, passage_position)
      end

      def retrieval_for(reference)
        slug = DocumentReference.new(reference).source_slug
        require_source(slug)
        maintained_retrieval(slug)
      end

      def passage_position
        position = Integer(parsed.fetch(:passage), exception: false).to_i
        return position if position.positive?

        raise CLI::Command::Usage, "passage must be a positive integer"
      end

      def require_source(slug)
        return if scope.known_slugs.include?(slug)

        raise CLI::Scope::UnknownProject, "no project named #{slug.inspect}"
      end

      def maintained_retrieval(slug)
        home = scope.plastic_home
        knowledge = File.join(home, "stores", slug, "knowledge_graph.db")
        complete = Graph::ReferenceBackfill.complete?(knowledge, Graph::Origin.new(home).id)
        raise Graph::RetrievalGraph::MaintenanceRequired, "retrieval maintenance is required before source #{slug} can be read" unless complete

        Graph.open_retrieval(home:, store: slug)
      end
    end
  end
end
