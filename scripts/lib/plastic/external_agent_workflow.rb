# frozen_string_literal: true

module Plastic
  # Gives an external agent deterministic retrieval commands without selecting evidence.
  class ExternalAgentWorkflow < AgentWorkflow
    class << self
      def retrieval_handoff(intent_id:, terms:, sources:)
        { "search" => search_command(terms, sources), "evidence" => "plastic document get REF",
          "architecture" => "external architecture provider records coverage and limitations",
          "context" => "plastic intent context #{intent_id} --from FILE" }
      end

      private

      def search_command(terms, sources)
        ["plastic search", terms, *sources.map { |source| "--source-project #{source}" }].join(" ")
      end
    end
  end
end
