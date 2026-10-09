# frozen_string_literal: true

require "json"
require_relative "../code_workflow"
require_relative "intent_id_format"
require_relative "discovery_scope"
require_relative "discovery_manifest"
require_relative "passage_rows"
require_relative "../graph/retrieval/search/excerpt"
require_relative "discovery_persistence"

module Plastic
  module Workflows
    # Records lexical retrieval candidates before an external agent selects them.
    class DiscoverRetrieval < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :intent, :source_scope, :discovery, :handoff_text, :context_command, :context_complete

      read "check the intent id" do |context|
        IntentIdFormat.validate(context.intent_id)
      end

      read "find the owning intent" do |context|
        context[:intent] = context.retrieval.intent(context.intent_id)
      end

      read "find the saved retrieval context" do |context|
        row = context.database(:knowledge).row("SELECT data FROM retrieval_contexts WHERE intent_id = :intent_id AND origin_id = :origin",
          intent_id: context.intent_id, origin: context.retrieval.origin_id)
        context[:context_complete] = context_matches?(row, context)
      end

      gate "no intent %{intent_id} in owning store", stops: :failure, pass: ->(context) { !context.intent.nil? }

      step "record retrieval discovery", done: ->(context) { !context.discovery.nil? } do |context|
        source_scope = DiscoveryScope.resolve(context)
        document = DiscoveryManifest.build(context, source_scope)
        DiscoveryPersistence.persist(context, document)
        context[:source_scope] = source_scope
        context[:discovery] = document
        context[:handoff_text] = "Submit the selected retrieval context with plastic intent context #{context.intent_id} --from FILE --project #{context.scope.slug}."
        context[:context_command] = document.fetch(:workflow).fetch("context")
      end

      read "report the discovery" do |context|
        context.row("discovery", printed(context))
      end

      outcome :done, offers: nil, because: "retrieval discovery is recorded"

      class << self
        private

        def printed(context)
          excerpt = Graph::Retrieval::Search::Excerpt.new(context.terms)
          discovery = context.discovery.transform_keys(&:to_s)
          discovery.merge("candidates" => PassageRows.new(passage_of: ->(row) { excerpt.call(row.fetch("body")) }).call(discovery.fetch("candidates")))
        end

        def context_matches?(row, context)
          return false unless row

          saved = JSON.parse(row.fetch("data")).fetch("discovery")
          saved.fetch("query") == context.terms && saved.fetch("scope") == DiscoveryScope.resolve(context)
        rescue JSON::ParserError, KeyError
          false
        end
      end
    end
  end
end
