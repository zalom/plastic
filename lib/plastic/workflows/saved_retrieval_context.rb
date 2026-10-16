# frozen_string_literal: true

require "json"
require_relative "discovery_scope"

module Plastic
  module Workflows
    # The retrieval context an intent saved for this installation, and
    # whether it answers the same query over the same stores.
    class SavedRetrievalContext
      def initialize(context)
        @context = context
      end

      def complete?
        row = @context.database(:knowledge).row("SELECT data FROM retrieval_contexts WHERE intent_id = :intent_id AND origin_id = :origin",
          intent_id: @context.intent_id, origin: @context.retrieval.origin_id)
        row ? matches?(JSON.parse(row.fetch("data")).fetch("discovery")) : false
      rescue JSON::ParserError, KeyError
        false
      end

      private

      def matches?(saved) = saved.fetch("query") == @context.terms && saved.fetch("scope") == DiscoveryScope.resolve(@context)
    end
  end
end
