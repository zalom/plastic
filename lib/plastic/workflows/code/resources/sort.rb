# frozen_string_literal: true

require_relative "../../../code_workflow"
require_relative "../../../graph"
require_relative "../../../graph/knowledge/resources/sort"

module Plastic
  module Workflows
    module Code
      module Resources
        # Moves the files of one store into the resources layout.
        class Sort < CodeWorkflow
          clear_declarations
          summary "Moves the files of one store into the resources layout and rewrites their links."

          sets :sorted

          def self.folder(context) = Plastic::Graph::Knowledge::StoreFolder.new(context.scope.root)

          def self.graphs(context) = Plastic::Graph::Graphs.new(work: context.work, retrieval: context.retrieval, databases: { store: context.database(:store) })

          def self.reports(context) = context.settings.selection.reports

          step "sort the files", done: ->(context) { !context.sorted.nil? },
            changes: { store: "Files move into the resources layout and the links that point at them are rewritten" } do |context|
            context[:sorted] = Plastic::Graph::Knowledge::Resources::Sort.new(folder(context), graphs(context), reports: reports(context)).call
          end

          read "say what was sorted" do |context|
            lines = context.sorted
            lines.each { |line| context.print(line) }
            context.print("sorted: nothing to move") if lines.empty?
          end

          outcome :done, offers: "plastic doctor", because: "the store holds its files in the resources layout"
        end
      end
    end
  end
end
