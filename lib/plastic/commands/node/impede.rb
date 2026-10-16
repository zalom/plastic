# frozen_string_literal: true

require_relative "../../routine"

module Plastic
  module Commands
    module Node
      # Moves a claimed node to impeded, with the impediment.
      class Impede < Routine
        node_subject
        argument :text, label: "TEXT", text: "the impediment"
        writes :work
        prints :intent

        workflow :code_impede_node, next: :noop
      end
    end
  end
end
