# frozen_string_literal: true

require_relative "../../routine"

module Plastic
  module Commands
    module Node
      # Adds one node to an intent's work graph, open and ready.
      class Add < Routine
        intent_subject
        argument :title, label: "TITLE", text: "what the node is for"
        option :criterion, switch: "--criterion KEY", text: "the key of the spec done criterion this node serves", required: true
        option :kind, switch: "--kind KIND", text: "orchestrator, work or retrieval; work when left out"
        option :found_in, switch: "--found-in NODE", text: "the node of this intent where the new work was found; it orders nothing"
        option :inputs, switch: "--input PATH", text: "a file the node reads; repeat for more, kept in the order given", repeatable: true
        option :deadline, switch: "--deadline MINUTES", text: "the minutes a claim on the node may run before plastic graph ready reports it as overdue"
        reads :knowledge
        writes :work
        prints :intent

        workflow :code_add_node, next: :noop

        MINUTES = /\A[1-9]\d*\z/

        def call
          minutes = parsed[:deadline]
          raise Usage, "--deadline takes a whole number of minutes above 0, such as 30" if minutes && !MINUTES.match?(minutes)
          raise Usage, "--input takes a path; an empty one names no file" if Array(parsed[:inputs]).any?(&:empty?)

          super
        end
      end
    end
  end
end
