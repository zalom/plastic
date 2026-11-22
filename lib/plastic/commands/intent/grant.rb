# frozen_string_literal: true

require_relative "../../routine"

module Plastic
  module Commands
    module Intent
      # Grants one extra review round to an intent whose rounds are used. Only the owner's word grants it, so --owner is required.
      class Grant < Routine
        intent_subject
        argument :reason, label: "REASON", text: "why the owner grants the round", rest: true
        option :owner, switch: "--owner", default: false, text: "the owner's word: a call without it grants nothing"
        reads :knowledge
        writes :work
        prints :intent

        workflow :code_grant_round, next: :noop

        def call(*)
          raise Usage, "a review round is granted on the owner's word: pass --owner" unless parsed[:owner]

          super
        end
      end
    end
  end
end
