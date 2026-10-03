# frozen_string_literal: true

module Plastic
  module Graph
    # Validates an archive request before it captures or removes a directory.
    class ArchiveGuard
      DONE_STATES = %w[done abandoned].freeze
      ARCHIVABLE_STATES = %w[done abandoned future].freeze

      def initialize(retrieval)
        @retrieval = retrieval
      end

      def problem(intent)
        return invalid_state(intent) unless ARCHIVABLE_STATES.include?(intent.status)

        live_link_problem(intent)
      end

      private

      attr_reader :retrieval

      def invalid_state(intent)
        "intent #{intent.intent_id} is #{intent.status}; only done, abandoned and future intents archive"
      end

      def live_link_problem(intent)
        link = retrieval.linking(intent.intent_id).find { |candidate| live?(candidate.from_ref) }
        "intent #{intent_id(link.from_ref)} links to #{intent.intent_id}" if link
      end

      def live?(from_ref)
        source = retrieval.intent(intent_id(from_ref))
        source && !DONE_STATES.include?(source.status) && !retrieval.archived?(source.intent_id)
      end

      def intent_id(reference) = reference.split("/").first
    end
  end
end
