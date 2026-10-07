# frozen_string_literal: true

require_relative "entry"
require_relative "../../prints"
require_relative "../store_folder"

module Plastic
  module Graph
    module Knowledge
      class Sync
        # Every path a sync looks at: the files of the store folder that can be
        # read, the paths of its prints and the paths of its rows.
        class EntryList
          def initialize(folder, retrieval, folders = nil)
            @folder = folder
            @retrieval = retrieval
            @folders = folders
          end

          def entries
            prints = Prints.of_store(@retrieval).to_h { |print| [print.path, print] }
            printed = @retrieval.printed
            (prints.keys | on_disk | printed.keys).sort.map do |path|
              Entry.new(path, @folder.digest(path), printed[path], prints.fetch(path, Entry::NO_PRINT))
            end
          end

          def on_disk
            files = @folders ? @folders.readable_files : @folder.intent_files
            [*(StoreFolder::INDEX if @folder.exist?(StoreFolder::INDEX)), *files]
          end
        end
      end
    end
  end
end
