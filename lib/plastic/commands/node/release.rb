# frozen_string_literal: true

require_relative "../../routine"

module Plastic
  module Commands
    module Node
      # Releases a claimed or failed node back to open.
      class Release < Routine
        node_subject
        writes :work
        prints :intent

        workflow :code_release_node, next: :noop
      end
    end
  end
end
