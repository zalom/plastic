# frozen_string_literal: true

require_relative "entry"
require_relative "../prints"
require_relative "../store_folder"

module Plastic
  module Graph
    module Knowledge
      class Sync
        # Every path a sync looks at: the files of the store folder that can be
        # read, the paths of its prints and the paths of its rows, each of a
        # kind the selection of the folder reads.
        class EntryList
          def initialize(folder, retrieval, folders = nil)
            @folder = folder
            @retrieval = retrieval
            @folders = folders
          end

          def entries
            printed = printed_hashes
            paths = printed.keys
            prints = prints_of(paths)
            selected = (prints.keys | on_disk | paths).select { |path| @folder.sync.selection.selects?(path) }
            selected.sort.map { |path| entry(path, printed[path], prints) }
          end

          def printed_hashes = @retrieval.stored.printed

          def entry(path, printed_sha, prints) = Entry.for(@folder, path, printed_sha, prints.fetch(path, Entry::NO_PRINT))

          def prints_of(printed_paths) = [*Prints.of_store(@retrieval), *parts(printed_paths)].to_h { |print| [print.path, print] }

          # The clusters and the links of the index, once the index is on disk or a part was printed.
          def parts(printed_paths)
            held = @folder.exist?(StoreFolder::INDEX) || printed_paths.any? { |path| Prints::Parts.path?(path) }
            held ? Prints.parts(@retrieval) : []
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
