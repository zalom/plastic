# frozen_string_literal: true

require_relative "../sort"
require_relative "../../../../code_workflow"
require_relative "../../../../graph/knowledge/resources/sort_plan"

module Plastic
  module Workflows
    module Code
      module Resources
        class Sort
          # Lists the moves, the links and the amendments a sort would change, and writes nothing.
          class Preview < CodeWorkflow
            clear_declarations
            summary "Previews a sort of the resources without moving a file."

            read "preview the sort" do |context|
              next unless context.dry_run

              reports = Code::Resources::Sort.reports(context).recorded_from(context.database(:store))

              sort_plan = Plastic::Graph::Knowledge::Resources::SortPlan
              plan = sort_plan.new(Code::Resources::Sort.folder(context), reports:, closed: sort_plan.closed(context.retrieval))
              plan.moves.each { |move| context.print(plan.preview(move)) }
              plan.changed.each { |link| context.print("preview: link would change #{link}") }
              plan.amendments.each { |amendment| context.print(amendment.preview) }
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
