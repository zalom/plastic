# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Moves a claimed node to parked, with a question for the owner.
    class NodePark < Routine
      node_subject
      option :question, switch: "--question TEXT", text: "what the owner must decide"
      writes :work

      workflow :code_park_node, next: :noop
    end
  end
end
