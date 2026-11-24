# frozen_string_literal: true

require_relative "../../routine"

module Plastic
  module Commands
    module Intent
      # Starts one intent for guided work: sets it in progress and prints its code worktree.
      class Start < Routine
        def self.given_facts = { start_words: "intent start", delivery: "guided" }

        intent_subject
        option :take_over, switch: "--take-over REASON", default: "", text: "the owner's word that this session takes over a live driver; the reason goes in the work log"
        writes :work, :knowledge
        prints :intent

        workflow :code_start_intent, next: :noop
      end
    end
  end
end
