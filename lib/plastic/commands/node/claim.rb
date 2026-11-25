# frozen_string_literal: true

require_relative "../../routine"

module Plastic
  module Commands
    module Node
      # Claims an open node: moves it to claimed and prints its brief.
      class Claim < Routine
        node_subject
        option :agent, switch: "--agent NAME", required: true, text: "the agent that runs the node, recorded on its run with its harness, model, tokens and cost"
        writes :work
        prints :intent

        workflow :code_claim_node, next: :noop
      end
    end
  end
end
