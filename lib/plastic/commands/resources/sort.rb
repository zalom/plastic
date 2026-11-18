# frozen_string_literal: true

require_relative "../../routine"
require_relative "../../cli/backup_store"

module Plastic
  module Commands
    module Resources
      # Moves the files of one store into the resources layout and rewrites the links that point at them.
      class Sort < Routine
        include CLI::BackupStore

        option :store, switch: "--store SLUG", required: true, text: "the registered project whose resources the call sorts"
        option :dry_run, switch: "--dry-run", default: false, text: "list the moves, the links that would change and the links left as they are, and move nothing"

        changes(knowledge: "The rows of the moved files move with them, and the rows of the files with changed links are rewritten",
          store: "The files move to resources/output, resources/references or resources/tmp, and the links that point at them are rewritten")

        backs_up_first

        workflow :code_preview_sort_resources do
          on :done, next: :noop
          on :continue, next: :code_sort_resources
        end
        workflow :code_sort_resources, next: :noop
      end
    end
  end
end
