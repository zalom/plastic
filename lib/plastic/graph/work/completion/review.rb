# frozen_string_literal: true

require "time"
require_relative "../../rows/verdict"
require_relative "../verdict/rounds"

module Plastic
  module Graph
    module Work
      module Completion
        # The judge's rounds of one intent: the verdict counts when it is the latest accept and no live node changed after it.
        # Once the rounds are used, the owner's handover to a follow-up intent settles the review in place of a verdict.
        class Review
          def self.of(context) = new(context.retrieval, context.intent_id)

          def initialize(retrieval, intent_id)
            @retrieval = retrieval
            @intent_id = intent_id
          end

          def counting? = latest&.verdict == "accept" && live_times.all? { |time| time <= Time.parse(latest.at) }

          def used_up? = !rounds.left? && !counting?

          def handed_over? = used_up? && rounds.handed_over?

          def settled? = counting? || handed_over?

          def problem = ("No accepted review counts yet. Run plastic intent judge #{@intent_id}." unless settled?)

          private

          def rounds = @rounds ||= Verdict::Rounds.new(@retrieval, @intent_id)

          def latest = @latest ||= @retrieval.structure.verdicts(@intent_id).max_by(&:round)

          def live_times = @retrieval.structure.nodes(@intent_id).select(&:live?).filter_map(&:changed_at)
        end
      end
    end
  end
end
