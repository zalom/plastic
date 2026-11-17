# frozen_string_literal: true

require_relative "../../routine"

module Plastic
  module Commands
    module Node
      # Renews the claim of this session on a node, so the claim does not lapse.
      class Renew < Routine
        node_subject
        writes :work
        prints :intent

        workflow :code_renew_node, next: :noop
      end
    end
  end
end
