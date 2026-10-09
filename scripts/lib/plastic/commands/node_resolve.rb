# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Reopens a needs_info or impeded node with its resolution and resets its
    # retries.
    class NodeResolve < Routine
      node_subject
      argument :text, label: "TEXT", text: "the resolution"
      writes :work

      workflow :code_resolve_node, next: :noop
    end
  end
end
