# frozen_string_literal: true

require_relative "../../routine"

module Plastic
  module Commands
    module Intent
      # Hands the last gap of an intent whose review rounds are used to a follow-up intent, so the intent can end with no
      # revert. Only the owner's word hands it over, so --owner is required.
      class Handover < Routine
        intent_subject
        argument :follow_up, label: "FOLLOW_UP", text: "the follow-up intent that takes over the last gap"
        argument :reason, label: "REASON", text: "why the owner hands the gap over", rest: true
        option :owner, switch: "--owner", default: false, text: "the owner's word: a call without it hands nothing over"
        reads :knowledge
        writes :work
        prints :intent

        workflow :code_hand_over_gap, next: :noop

        def call(*)
          raise Usage, "a gap is handed over on the owner's word: pass --owner" unless parsed[:owner]

          super
        end
      end
    end
  end
end
