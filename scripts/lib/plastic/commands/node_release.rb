# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Releases a claimed or failed node back to open.
    class NodeRelease < Routine
      subject :intent_id, :id
      argument :intent_id, label: "ID", text: "the intent"
      argument :id, label: "NODE", text: "the node"
      writes :work

      workflow :code_release_node, next: :noop
    end
  end
end
