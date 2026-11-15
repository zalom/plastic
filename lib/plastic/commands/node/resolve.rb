# frozen_string_literal: true

require_relative "move"

module Plastic
  module Commands
    module Node
      # Reopens a needs_info or impeded node with its resolution and resets its
      # retries.
      class Resolve < Move
        argument :text, label: "TEXT", text: "the resolution"

        workflow :code_resolve_node, next: :noop
      end
    end
  end
end
