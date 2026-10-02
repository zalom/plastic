# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Answers a parked node's question, moving it back to open with its
    # retries reset.
    class NodeAnswer < Routine
      node_subject
      option :answer, switch: "--answer TEXT", text: "the owner's answer"
      writes :work

      workflow :code_answer_node, next: :noop
    end
  end
end
