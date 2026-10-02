# frozen_string_literal: true

require_relative "../cli/command"
require_relative "../graph"

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
      end

      private

      def fetch(reference)
        retrieval_for(reference).fetch_reference(reference)
      rescue Graph::RetrievalGraph::MissingReference, Graph::RetrievalGraph::MaintenanceRequired, CLI::Scope::UnknownProject => error
        raise CLI::Command::Failure, error.message
      end

      def selected(reference)
        return fetch(reference) unless parsed[:passage]

        retrieval_for(reference).fetch_passage(reference, Integer(parsed.fetch(:passage)))
      end

      def retrieval_for(reference)
        slug = source_slug(reference)
        validate_source!(slug)
        maintained_retrieval(slug)
      end

      def source_slug(reference)
        slug = reference[/\Aplastic:\/\/([^\/]+)/, 1]
        raise CLI::Command::Usage, "invalid document reference #{reference.inspect}" unless slug

        slug
      end

      def validate_source!(slug)
        return if scope.known_slugs.include?(slug)

        raise CLI::Scope::UnknownProject, "no project named #{slug.inspect}"
      end

      def maintained_retrieval(slug)
        knowledge = File.join(scope.plastic_home, "stores", slug, "knowledge_graph.db")
        complete = Graph::ReferenceBackfill.complete?(knowledge, Graph::Origin.new(scope.plastic_home).id)
        raise Graph::RetrievalGraph::MaintenanceRequired, "retrieval maintenance is required before source #{slug} can be read" unless complete

        Graph.open(home: scope.plastic_home, store: slug).retrieval
      end
    end
  end
end
