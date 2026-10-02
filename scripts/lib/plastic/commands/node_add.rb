# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Adds one node to an intent's work graph, open and ready.
    class NodeAdd < Routine
      intent_subject
      argument :title, label: "TITLE", text: "what the node is for"
      option :criterion, switch: "--criterion TEXT", text: "what done means", required: true
      option :input, switch: "--input PATH", text: "a file the node reads"
      writes :work

      workflow :code_add_node, next: :noop
    end
  end
end
