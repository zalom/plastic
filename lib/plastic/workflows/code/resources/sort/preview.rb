# frozen_string_literal: true

require_relative "../sort"
require_relative "../../../../code_workflow"
require_relative "../../../../graph/knowledge/resources/sort_plan"

module Plastic
  module Workflows
    module Code
      module Resources
        class Sort
          # Lists the moves and the links a sort would change, and writes nothing.
          class Preview < CodeWorkflow
            clear_declarations
            summary "Previews a sort of the resources without moving a file."

            read "preview the sort" do |context|
              next unless context.dry_run

              plan = Plastic::Graph::Knowledge::Resources::SortPlan.new(Code::Resources::Sort.folder(context))
              plan.moves.each { |move| context.print("preview: move #{move.from} -> #{move.to}") }
              plan.unresolved.each { |link| context.print("preview: link left as it is #{link}") }
              context.print("preview complete; the original store was not changed")
            end

            outcome :done, if: ->(context) { context.dry_run }, offers: "%{original_command}",
              because: "the preview moved no file"
            outcome :continue, offers: "plastic resources sort --store %{store}", because: "apply the requested sort"
          end
        end
      end
    end
  end
end
