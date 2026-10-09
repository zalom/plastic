# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Rewrites the What and the Why of an intent after grilling. The old
    # text stays as an earlier revision of the intent's file.
    class IntentRevise < Routine
      intent_subject
      argument :line, label: "LINE", text: "the new What, the intent line"
      option :why, switch: "--why TEXT", text: "the new Why, the lead text of ## Context"
      option :dry_run, switch: "--dry-run", default: false, text: "print the change and write nothing"
      writes :work, :knowledge

      workflow :code_revise_intent, next: :noop

      private
    end
  end
end
