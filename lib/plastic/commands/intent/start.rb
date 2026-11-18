# frozen_string_literal: true

require_relative "../../routine"

module Plastic
  module Commands
    module Intent
      # Starts one intent for guided work: sets it in progress and prints its code worktree.
      class Start < Routine
        def self.given_facts = { start_words: "intent start" }

        intent_subject
        writes :work, :knowledge
        prints :intent

        workflow :code_start_intent, next: :noop
      end
    end
  end
end
