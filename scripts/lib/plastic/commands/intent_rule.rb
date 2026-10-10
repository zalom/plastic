# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Writes one owner ruling against an intent, numbered D1, D2 and on.
    # --supersedes names an older ruling and links the two.
    class IntentRule < Routine
      intent_subject
      argument :text, label: "TEXT", text: "the ruling, in the owner's words"
      option :supersedes, switch: "--supersedes RULING_ID", text: "an older ruling this one replaces"
      writes :knowledge
      prints :intent

      workflow :code_add_ruling, next: :noop
    end
  end
end
