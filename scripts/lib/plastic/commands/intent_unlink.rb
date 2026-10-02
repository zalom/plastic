# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Removes one `links` row from ID to TARGET of the given kind.
    class IntentUnlink < Routine
      subject :intent_id
      argument :intent_id, label: "ID", text: "the intent this link starts from"
      argument :kind, label: "KIND", text: "cites, supersedes, answers, source or chain"
      argument :target, label: "TARGET", text: "the link's other end, as written when it was added"
      writes :knowledge

      workflow :code_remove_link, next: :noop
    end
  end
end
