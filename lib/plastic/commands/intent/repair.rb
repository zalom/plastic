# frozen_string_literal: true

require_relative "../../routine"

module Plastic
  module Commands
    module Intent
      # Applies the folder layout to the folder of one intent, or with --all to every intent folder and the store folder.
      class Repair < Routine
        def self.usage_line(tool = tool_name) = super.sub("[ID] [--all]", "(ID | --all)")

        subject :intent_id
        argument :intent_id, label: "ID", text: "the intent whose folder to repair", optional: true
        option :all, switch: "--all", default: false, text: "repair every intent folder of the store, and remove the retired entries of its store folder"
        option :dry_run, switch: "--dry-run", default: false,
          text: "list one line for each intent folder the repair would change, the links that would change and the amendments of closed intents, then the totals, and change nothing"
        option :links_left, switch: "--links-left", default: false,
          text: "also list each link the repair leaves as it is, which the totals otherwise count"
        writes :retrieval

        changes(knowledge: "The rows of the moved files move with them, the rows of the removed files go, and the rows of the files with changed links are rewritten",
          store: "Files are renamed, moved or removed where the layout says, the links that point at them are rewritten, and with --all the retired entries of the store folder go",
          work: "A done or abandoned intent gets one amended work log line for the renames, moves and removals of its folder and one for each link it changes, and each entry of an old revisions.md gets one, printed to its work.log")

        backs_up_first

        holds_store_lock

        workflow :code_preview_repair_intent do
          on :done, next: :noop
          on :continue, next: :code_repair_intent
        end
        workflow :code_repair_intent, next: :noop

        def call
          check_choice
          super
        end

        private

        def check_choice
          given = [parsed[:intent_id], parsed[:all]].count { |value| value }
          raise Usage, "give an intent ID or --all" if given.zero?
          raise Usage, "an intent ID and --all exclude each other" if given > 1
        end
      end
    end
  end
end
