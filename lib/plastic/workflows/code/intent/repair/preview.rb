# frozen_string_literal: true

require_relative "../repair"
require_relative "../../../../code_workflow"
require_relative "../../../../graph/knowledge/repair/plan"

module Plastic
  module Workflows
    module Code
      module Intent
        class Repair
          # Checks the folders a repair names, and with --dry-run lists every change the repair would make and writes nothing.
          class Preview < CodeWorkflow
            Knowledge = Plastic::Graph::Knowledge

            clear_declarations
            summary "Checks the folders of a repair and previews it without changing a file."

            sets :held, :held_dirs

            def self.plan(context)
              reports = Repair.reports(context).recorded_from(context.database(:store))
              retrieval = context.retrieval
              closed = Knowledge::Resources::SortPlan.closed(retrieval)
              states = Knowledge::Repair::MissingFiles.states(retrieval.intents)
              Knowledge::Repair::Plan.new(Repair.folder(context), reports:, closed:, states:, dirs: Repair.dirs(context), held: context.held.to_set)
            end

            def self.lines(context)
              leftovers = Repair.leftovers(context)
              [*plan(context).preview, *leftovers&.preview, *leftovers&.left&.map { |line| "preview: #{line}" }]
            end

            read "find the folders a claim holds" do |context|
              Repair.find_held(context)
            end

            gate "intent %{intent_id} has no folder in the store", stops: :failure, offers: "plastic status",
              because: "a repair changes only folders that exist", pass: ->(context) { context.all || Repair.dirs(context).any? }
            gate Repair::HELD, stops: :refusal, offers: "plastic status",
              because: "a repair moves no file under a session at work", pass: ->(context) { context.all || context.held.empty? }

            read "preview the repair" do |context|
              next unless context.dry_run

              lines = lines(context)
              lines.each { |line| context.print(line) }
              context.print("preview: nothing to change") if lines.empty?
              context.print("preview complete; the original store was not changed")
            end

            gate Repair::HELD, stops: :refusal, offers: "plastic status",
              because: "the repair would move no file under a session at work", pass: ->(context) { !context.dry_run || context.held.empty? }

            outcome :done, if: ->(context) { context.dry_run }, offers: "%{original_command}", because: "the preview changed no file"
            outcome :continue, offers: "plastic intent repair", because: "apply the requested repair"
          end
        end
      end
    end
  end
end
