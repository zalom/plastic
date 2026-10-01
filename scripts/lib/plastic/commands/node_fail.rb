# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Moves a claimed node to failed, with a reason.
    class NodeFail < Routine
      subject :intent_id, :id
      argument :intent_id, label: "ID", text: "the intent"
      argument :id, label: "NODE", text: "the node"
      option :reason, switch: "--reason TEXT", text: "why it failed"
      writes :work

      workflow :code_fail_node, next: :noop
    end
  end
end
