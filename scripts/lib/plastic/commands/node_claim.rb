# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Claims an open node: moves it to claimed and prints its brief.
    class NodeClaim < Routine
      node_subject
      writes :work

      workflow :code_claim_node, next: :noop
    end
  end
end
