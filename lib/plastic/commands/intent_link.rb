# frozen_string_literal: true

require_relative "../routine"
require_relative "../graph/knowledge/link"

module Plastic
  module Commands
    # Writes one `links` row from ID to TARGET: an intent id, a ruling ref
    # such as `1/D1`, or a ref with a store prefix such as `global:25`.
    class IntentLink < Routine
      subject :intent_id
      argument :intent_id, label: "ID", text: "the intent this link starts from"
      argument :kind, label: "KIND", text: "cites, supersedes, answers, source or chain"
      argument :target, label: "TARGET", text: "an intent, a ruling, or a ref with a store prefix"
      reads :work
      writes :knowledge
      prints :intent

      def call
        raise CLI::Command::Usage, "KIND takes #{Graph::Knowledge::Link::KINDS.join(", ")}" unless Graph::Knowledge::Link::KINDS.include?(parsed[:kind])

        super
      end

      workflow :code_add_link, next: :noop
    end
  end
end
