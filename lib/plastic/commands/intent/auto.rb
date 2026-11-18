# frozen_string_literal: true

require_relative "../../routine"

module Plastic
  module Commands
    module Intent
      # Starts one intent for agent delivery: sets it in progress and prints its code worktree.
      class Auto < Routine
        def self.given_facts = { start_words: "intent auto" }

        intent_subject
        writes :work, :knowledge
        prints :intent

        workflow :code_start_auto, next: :noop
      end
    end
  end
end
