# frozen_string_literal: true

module Plastic
  module Commands
    # Confirms that a context request names an existing intent in its owning store.
    class ContextOwner
      def initialize(scope)
        @scope = scope
      end

      def validate(intent_id)
        validate_id(intent_id)
        return if owner_graph.retrieval.intent(intent_id)

        raise CLI::Command::Failure, "no intent #{intent_id} in owning store"
      end

      private

      attr_reader :scope

      def validate_id(intent_id)
        return if /\A\d+[a-z0-9]*\z/.match?(intent_id)

        raise CLI::Command::Usage, "invalid intent id #{intent_id.inspect}"
      end

      def owner_graph = Graph.open(home: scope.plastic_home, store: scope.slug)
    end
  end
end
