# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Claims an open node: moves it to claimed and prints its brief.
    class NodeClaim < Routine
      subject :intent_id, :id
      argument :intent_id, label: "ID", text: "the intent"
      argument :id, label: "NODE", text: "the node"
      writes :work

      workflow :code_claim_node, next: :noop
    end
  end
end
