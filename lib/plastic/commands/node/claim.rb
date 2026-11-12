# frozen_string_literal: true

require_relative "../../routine"

module Plastic
  module Commands
    module Node
      # Claims an open node: moves it to claimed and prints its brief.
      class Claim < Routine
        node_subject
        writes :work
        prints :intent

        workflow :code_claim_node, next: :noop
      end
    end
  end
end
