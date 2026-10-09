# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Moves a claimed node to needs_info, with the question for the owner.
    class NodeAsk < Routine
      node_subject
      argument :text, label: "TEXT", text: "the question and what was tried"
      writes :work

      workflow :code_ask_node, next: :noop
    end
  end
end
