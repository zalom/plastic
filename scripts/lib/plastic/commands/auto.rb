# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Delivers one intent or one roadmap in auto mode: picks the intent,
    # takes the lock, sets it active and prints its code worktree.
    class Auto < Routine
      subject :id
      argument :id, label: "ID", text: "the intent id or the roadmap slug"
      writes :work
      prints :intent

      workflow :code_pick_delivery, next: :noop do
        on :intent, next: :code_start_auto
      end
      workflow :code_start_auto, next: :noop
    end
  end
end
