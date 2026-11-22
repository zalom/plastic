# frozen_string_literal: true

require_relative "move"

module Plastic
  module Commands
    module Node
      # Moves a claimed node to done, with its findings. A done node takes new findings in place of the old.
      class Done < Move
        argument :text, label: "TEXT", text: "what the work showed"

        reads_files

        option :output, switch: "--output PATH", text: "a file of JSON to store as the output of the node, which the nodes that need it read; refused when it is not JSON; the path is read relative to the current directory"

        workflow :code_done_node, next: :noop
      end
    end
  end
end
