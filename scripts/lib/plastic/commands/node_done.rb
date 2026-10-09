# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Moves a claimed node to done, with its findings. A done node takes new findings in place of the old.
    class NodeDone < Routine
      node_subject
      argument :text, label: "TEXT", text: "what the work showed"
      writes :work

      workflow :code_done_node, next: :noop
    end
  end
end
