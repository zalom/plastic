# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Moves a claimed node to failed, with a reason.
    class NodeFail < Routine
      node_subject
      option :reason, switch: "--reason TEXT", text: "why it failed"
      writes :work

      workflow :code_fail_node, next: :noop
    end
  end
end
