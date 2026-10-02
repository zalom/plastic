# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Releases a claimed or failed node back to open.
    class NodeRelease < Routine
      node_subject
      writes :work

      workflow :code_release_node, next: :noop
    end
  end
end
