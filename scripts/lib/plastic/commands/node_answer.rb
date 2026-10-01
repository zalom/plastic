# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Answers a parked node's question, moving it back to open with its
    # retries reset.
    class NodeAnswer < Routine
      subject :intent_id, :id
      argument :intent_id, label: "ID", text: "the intent"
      argument :id, label: "NODE", text: "the node"
      option :answer, switch: "--answer TEXT", text: "the owner's answer"
      writes :work

      workflow :code_answer_node, next: :noop
    end
  end
end
