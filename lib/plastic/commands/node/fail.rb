# frozen_string_literal: true

require_relative "move"

module Plastic
  module Commands
    module Node
      # Moves a claimed node to failed, with the reason.
      class Fail < Move
        argument :text, label: "TEXT", text: "why it failed"

        reads_files

        workflow :code_fail_node, next: :noop
      end
    end
  end
end
