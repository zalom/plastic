# frozen_string_literal: true

require_relative "move"

module Plastic
  module Commands
    module Node
      # Moves a claimed node to done, with its findings. A done node takes new findings in place of the old.
      class Done < Move
        argument :text, label: "TEXT", text: "what the work showed"

        workflow :code_done_node, next: :noop
      end
    end
  end
end
