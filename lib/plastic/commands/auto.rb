# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Delivers one intent or one roadmap in auto mode: picks the intent,
    # takes the lock, sets it in progress and prints its code worktree.
    class Auto < Routine
      subject :id
      argument :id, label: "ID", text: "the intent id or the roadmap slug"
      writes :work, :knowledge
      prints :intent

      workflow :code_pick_delivery, next: :noop do
        on :intent, next: :code_start_auto
      end
      workflow :code_start_auto, next: :noop

      # The files to check are those of the intent the word picks, which no fact holds before the workflow runs.
      def self.picked(ctx) = { intent_id: Workflows::Code::Auto::Pick.intent_for(ctx) }

      private

      def picked_facts(ctx) = self.class.picked(ctx)
    end
  end
end
