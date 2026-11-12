# frozen_string_literal: true

require_relative "../archive"

module Plastic
  module Graph
    module Knowledge
      class Archive
        # Validates an archive request before it captures or removes a directory.
        class Guard
          DONE_STATES = %w[done abandoned].freeze

          def initialize(retrieval)
            @retrieval = retrieval
          end

          def problem(intent) = intent.archive_refusal || live_link_problem(intent)

          private

          attr_reader :retrieval

          def live_link_problem(intent)
            target = intent.intent_id
            link = retrieval.linking(target).find { |candidate| live?(candidate.from_intent_id) }
            "intent #{link.from_intent_id} links to #{target}" if link
          end

          def live?(source_id)
            source = retrieval.intent(source_id)
            source && !DONE_STATES.include?(source.status) && !retrieval.archived?(source.intent_id)
          end
        end
      end
    end
  end
end
