# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Takes a done, abandoned or future intent off the checkout; its rows stay.
    class IntentArchive < Routine
      subject :intent_id
      argument :intent_id, label: "ID", text: "the intent to archive"
      writes :work, :knowledge, :references
      prints :index
      previews

      workflow :code_archive_intent, next: :noop
    end
  end
end
