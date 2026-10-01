# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Removes one edge. Fails when no such edge exists.
    class EdgeRemove < Routine
      subject :intent_id
      argument :intent_id, label: "ID", text: "the intent"
      argument :from, label: "FROM", text: "the edge's start"
      argument :to, label: "TO", text: "the edge's end"
      writes :work

      workflow :code_remove_edge, next: :noop
    end
  end
end
