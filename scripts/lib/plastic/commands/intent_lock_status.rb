# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Prints the session that holds an intent's lock, and its code worktree.
    class IntentLockStatus < Routine
      intent_subject
      reads :work

      workflow :code_show_lock do
        on :none, next: :noop
        on :expired, next: :noop
        on :live, next: :noop
        on :agent_needed, next: :agent_advance_delivery
      end
      workflow :agent_advance_delivery, next: :noop
    end
  end
end
