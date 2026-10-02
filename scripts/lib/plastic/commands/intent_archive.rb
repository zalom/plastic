# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Takes a done, abandoned or future intent off the checkout; its rows stay.
    class IntentArchive < Routine
      subject :intent_id, :revert
      argument :intent_id, label: "ID", text: "the intent to archive"
      option :revert, switch: "--revert", text: "restore the archived directory exactly"
      writes :work, :knowledge, :references

      workflow :code_choose_archive do
        on :archive, next: :code_archive_intent
        on :revert, next: :code_restore_intent
      end
      workflow :code_archive_intent, next: :noop
      workflow :code_restore_intent, next: :noop
    end
  end
end
