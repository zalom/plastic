# frozen_string_literal: true

require_relative "../../routine"

module Plastic
  module Commands
    module Roadmap
      # Starts a roadmap's next item for agent delivery: its first free item in
      # flight, or its first ready item, opened first.
      class Auto < Routine
        def self.given_facts = { start_words: "intent auto" }

        subject :slug
        argument :slug, label: "SLUG", text: "the roadmap"
        writes :work, :knowledge, :retrieval
        prints :roadmap, :intent

        workflow :code_auto_roadmap, next: :noop do
          on :intent, next: :code_open_roadmap_item
          on :ready, next: :code_open_roadmap_item
        end
        workflow :code_open_roadmap_item, next: :code_start_intent
        workflow :code_start_intent, next: :noop

        # The files to check are those of the intent the roadmap picks, which no fact holds before the workflow runs.
        def self.hand_edit_additions(ctx) = { intent_id: Workflows::Code::Roadmap::Auto.intent_for(ctx) }
      end
    end
  end
end
