# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Moves a claimed node to parked, with a question for the owner.
    class NodePark < Routine
      subject :intent_id, :id
      argument :intent_id, label: "ID", text: "the intent"
      argument :id, label: "NODE", text: "the node"
      option :question, switch: "--question TEXT", text: "what the owner must decide"
      writes :work

      workflow :code_park_node, next: :noop
    end
  end
end
