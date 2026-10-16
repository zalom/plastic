# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Moves a node from open to removed. Its edges stay, but a removed node
    # never counts as ready or isolated.
    class NodeRemove < Routine
      node_subject
      option :reason, switch: "--reason TEXT", text: "why the node is removed"
      writes :work
      prints :intent
      previews

      workflow :code_remove_node, next: :noop
    end
  end
end
