# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Moves a claimed node to impeded, with the impediment.
    class NodeImpede < Routine
      node_subject
      argument :text, label: "TEXT", text: "the impediment"
      writes :work

      workflow :code_impede_node, next: :noop
    end
  end
end
