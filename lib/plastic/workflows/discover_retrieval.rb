# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "intent_id_format"
require_relative "discovery_scope"
require_relative "discovery_manifest"
require_relative "discovery_row"
require_relative "discovery_persistence"
require_relative "retrieval_repair"
require_relative "saved_retrieval_context"

module Plastic
  module Workflows
    # Records lexical retrieval candidates before an external agent selects them.
    class DiscoverRetrieval < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :intent, :source_scope, :discovery, :handoff_text, :context_command, :context_complete, :problem

      forget_stop :problem

      read "check the intent id" do |context|
        IntentIdFormat.validate(context.intent_id)
      end

      read "find the owning intent" do |context|
        context[:intent] = context.retrieval.intent(context.intent_id)
      end

      read "find the saved retrieval context" do |context|
        context[:context_complete] = SavedRetrievalContext.new(context).complete?
      end

      gate "no intent %{intent_id} in owning store", stops: :failure, pass: ->(context) { !context.intent.nil? }

      read "check the source stores" do |context|
        context[:problem] = RetrievalRepair.check(context.scope, DiscoveryScope.resolve(context))
      end

      gate "%{problem}", stops: :failure, pass: ->(context) { context.problem.nil? }

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
        context.row("discovery", DiscoveryRow.new(context).to_h)
      end

      outcome :done, offers: nil, because: "retrieval discovery is recorded"
    end
  end
end
