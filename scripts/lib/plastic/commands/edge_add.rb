# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Adds a needs edge between two nodes of the same intent, guarded
    # against a self edge, a missing or removed node, and a loop.
    class EdgeAdd < Routine
      subject :intent_id
      argument :intent_id, label: "ID", text: "the intent"
      argument :from, label: "FROM", text: "the node that must be done first"
      argument :to, label: "TO", text: "the node that waits on it"
      writes :work

      workflow :code_add_edge, next: :noop
    end
  end
end
