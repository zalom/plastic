# frozen_string_literal: true

require_relative "move"

module Plastic
  module Commands
    module Node
      # Moves a claimed node to needs_info, with the question for the owner.
      class Ask < Move
        argument :text, label: "TEXT", text: "the question and what was tried"

        workflow :code_ask_node, next: :noop
      end
    end
  end
end
