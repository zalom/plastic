# frozen_string_literal: true

require_relative "../../../code_workflow"
require_relative "../../../graph"
require_relative "../../../graph/knowledge/repair/run"
require_relative "../../../graph/knowledge/repair/holds"
require_relative "../../../graph/knowledge/repair/store_leftovers"

module Plastic
  module Workflows
    module Code
      module Intent
        # Applies the folder layout to the folder of one intent, or to every intent folder and the store folder.
        class Repair < CodeWorkflow
          Knowledge = Plastic::Graph::Knowledge

          clear_declarations
          summary "Applies the folder layout to intent folders and records each change to a closed intent."

          sets :repaired, :held, :held_dirs

          # The folders the call names: the folder of the intent, or every intent folder with --all.
          def self.dirs(context)
            dirs = folder(context).intent_dirs
            context.all ? dirs : dirs.select { |dir| Knowledge::SyncSelection.intent_of(dir) == context.intent_id }
          end

          # Sets the facts :held, the folders a claim holds, and :held_dirs, the same folders in one line.
          def self.find_held(context)
            held = Knowledge::Repair::Holds.new(context.work, context.retrieval, context.now).of(dirs(context)).sort
            context[:held] = held
            context[:held_dirs] = held.join(", ")
          end

          HELD = "held %{held_dirs}: #{Knowledge::Repair::Holds::WHY}".freeze

          def self.folder(context) = Knowledge::StoreFolder.new(context.scope.root)

          def self.graphs(context) = Plastic::Graph::Graphs.new(work: context.work, retrieval: context.retrieval, databases: { store: context.database(:store) })

          def self.reports(context) = context.settings.selection.reports

          def self.leftovers(context) = context.all ? Knowledge::Repair::StoreLeftovers.new(folder(context)) : nil

          def self.repair(context)
            run = Knowledge::Repair::Run.new(folder(context), graphs(context), reports: reports(context), dirs: dirs(context), held: context.held.to_set,
              links_left: context.links_left)
            [*run.call, *leftovers(context)&.call]
          end

          read "find the folders a claim holds" do |context|
            find_held(context)
          end

          step "repair the folders", done: ->(context) { !context.repaired.nil? },
            changes: { store: "Files are renamed, moved or removed where the layout says, the links that point at them are rewritten, and with --all the retired entries of the store folder go" } do |context|
            context[:repaired] = repair(context)
          end

          read "say what was repaired" do |context|
            lines = context.repaired
            lines.each { |line| context.print(line) }
            context.print("repaired: nothing to change") if lines.empty?
            # The next call repairs again, so a refusal below never replays these lines.
            context[:repaired] = nil
          end

          gate HELD, stops: :refusal, offers: "plastic status",
            because: "a repair moves no file under a session at work", pass: ->(context) { context.held.empty? }

          outcome :done, offers: "plastic doctor", because: "the folders hold their files where the layout names"
        end
      end
    end
  end
end
