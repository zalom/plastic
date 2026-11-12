# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Moves a claimed node to failed, with the reason.
    class NodeFail < Routine
      node_subject
      argument :text, label: "TEXT", text: "why it failed"
      writes :work
      prints :intent

      workflow :code_fail_node, next: :noop
    end
  end
end
