# frozen_string_literal: true

require_relative "intent_folder"
require_relative "../store_folder"

module Plastic
  module Graph
    module Knowledge
      class Sync
        # The intent folders of a store, whatever store/index.json says. A
        # folder whose intent has no row gives a row built from the fields of
        # its own file, the way the legacy import builds one. A folder that
        # cannot give a row is a problem named with its reason, and none of its
        # files are read.
        class IntentFolders
          def initialize(folder, retrieval)
            @store = folder
            @rowed = retrieval.intents.to_h { |intent| [intent.intent_id, intent.dir] }
            @folders = folder.intent_dirs.map { |dir| IntentFolder.new(dir, folder) }
          end

          # The intents of the folders that have no row and can be read.
          def intents = checked.filter_map { |folder, problem| folder.intent unless problem }

          # One line for each folder that cannot be read: its path and the reason.
          def problems = checked.values.compact

          # The paths of the folders that cannot be read.
          def unreadable = checked.filter_map { |folder, problem| folder.dir if problem }

          # Writes the rows of the readable folders that have none, in one transaction.
          def write_to(databases)
            rows = intents.map(&:new_row)
            databases.fetch(:work).transaction { |batch| batch.put_all(:intents, rows) } if rows.any?
          end

          # The intent files of the store that sit in a folder which can be read.
          def readable_files = @store.intent_files.reject { |path| unreadable?(path) }

          private

          def unreadable?(path) = unreadable.any? { |dir| path.start_with?("#{dir}/") }

          def checked = (@checked ||= unrowed.to_h { |folder| [folder, folder.clash_among(@folders) || folder.problem] })

          def unrowed = @folders.reject { |folder| @rowed[folder.number] == folder.dir }
        end
      end
    end
  end
end
