# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Prints the session that holds an intent's lock, and its code worktree.
    class IntentLockStatus < Routine
      intent_subject
      reads :work

      workflow :code_show_lock, next: :noop
    end
  end
end
