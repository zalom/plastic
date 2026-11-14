# frozen_string_literal: true

require_relative "entry"
require_relative "entry_files"
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
            printed = @retrieval.printed
            paths = printed.keys
            prints = prints_of(paths)
            (prints.keys | on_disk | paths).sort.map { |path| entry(path, printed[path], prints) }
          end

          def entry(path, printed_sha, prints) = EntryFiles.new(@folder).entry(path, printed_sha, prints.fetch(path, Entry::NO_PRINT))

          def prints_of(printed_paths) = self.class.by_path(Prints.of_store(@retrieval)).merge(roadmap_prints(printed_paths))

          # The roadmaps this home printed that still have rows, so a sync can print them again.
          def roadmap_prints(paths) = self.class.by_path(roadmap_slugs(paths).map { |slug| Prints.roadmap(@retrieval, slug) })

          def roadmap_slugs(paths) = paths.filter_map { |path| path[%r{\Aroadmaps/(.+)\.md\z}, 1] }.select { |slug| @retrieval.roadmap(slug) }

          def self.by_path(prints) = prints.to_h { |print| [print.path, print] }

          def on_disk
            files = @folders ? @folders.readable_files : @folder.intent_files
            [*(StoreFolder::INDEX if @folder.exist?(StoreFolder::INDEX)), *files]
          end
        end
      end
    end
  end
end
