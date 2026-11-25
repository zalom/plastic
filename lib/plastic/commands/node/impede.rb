# frozen_string_literal: true

require_relative "move"

module Plastic
  module Commands
    module Node
      # Moves a claimed node to impeded, with the impediment.
      class Impede < Move
        argument :text, label: "TEXT", text: "the impediment"

        reads_files

        workflow :code_impede_node, next: :noop
      end
    end
  end
end
