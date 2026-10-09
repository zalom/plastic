# frozen_string_literal: true

require "time"
require_relative "../verdict"

module Plastic
  module Graph
    module Work
      module Completion
        # The judge's rounds of one intent: the verdict counts when it is the latest accept and no live node changed after it.
        class Review
          def initialize(retrieval, intent_id)
            @retrieval = retrieval
            @intent_id = intent_id
          end

          def counting? = latest&.verdict == "accept" && live_times.all? { |time| time <= Time.parse(latest.at) }

          def used_up? = latest&.verdict == "revise" && latest.round >= Verdict::ROUNDS

          def problem = ("No accepted review counts yet. Run plastic intent judge #{@intent_id}." unless counting?)

          private

          def latest = @latest ||= @retrieval.verdicts(@intent_id).max_by(&:round)

          def live_times = @retrieval.nodes(@intent_id).reject { |node| node.state == "removed" }.filter_map { |node| node.updated_at && Time.parse(node.updated_at) }
        end
      end
    end
  end
end
