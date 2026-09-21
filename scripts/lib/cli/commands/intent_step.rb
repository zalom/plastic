# frozen_string_literal: true

require_relative "intent_command"

# `plastic intent step` - runs the graph's next ready step (`runner step`, run
# through Legacy). An intent with no `graph.md` gets the four-line non-graph
# procedure printed alongside it, since there is no graph for `step` itself
# to drive.
module Plastic
  class CLI
    module Commands
      class IntentStep < IntentCommand
        USAGE_LINE = "plastic intent step ID [--json]"

        SCRIPT = "runner"
        AFTER = "plastic intent step ID"
        BECAUSE = "call step again after each dispatched node returns"

        NON_GRAPH_WORK = [
          "no graph.md: dispatch ONE plastic-executor subagent with the whole consolidated action pasted in, never a file reference",
          "it writes the matrix's tests and commits them red, implements the action in order, and drives the suite green",
          "a tick is two edits made together: mark the item's box [x], and move it from ## In Progress to ## Completed",
          "add one ## Session Log row per tick; never batch several tasks into one later edit",
        ].freeze

        def call
          super
          @output.row("non-graph work", NON_GRAPH_WORK) unless graph?
        end

        private

        def graph?
          File.exist?(File.join(intent_dir, "graph.md"))
        end

        def script_arguments
          ["step", intent_dir]
        end
      end
    end
  end
end
