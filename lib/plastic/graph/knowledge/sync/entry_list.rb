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
            printed = @retrieval.printed
            paths = printed.keys
            prints = prints_of(paths)
            (prints.keys | on_disk | paths).sort.map { |path| entry(path, printed[path], prints) }
          end

          def entry(path, printed_sha, prints) = Entry.for(@folder, path, printed_sha, prints.fetch(path, Entry::NO_PRINT))

          def prints_of(printed_paths) = [*Prints.of_store(@retrieval), *cluster_part(printed_paths)].to_h { |print| [print.path, print] }.merge(roadmap_prints(printed_paths))

          # The clusters of the index, once the index is on disk or its clusters were printed.
          def cluster_part(printed_paths)
            held = @folder.exist?(StoreFolder::INDEX) || printed_paths.include?(Prints::ClusterPart::PATH)
            held ? [Prints.cluster_part(@retrieval)] : []
          end

          # The roadmaps this home printed or holds a file for that still have rows, so a sync can compare them.
          def roadmap_prints(paths)
            slugs = [*paths, *@folder.roadmap_files].filter_map { |path| path[%r{\Aroadmaps/(.+)\.md\z}, 1] }.uniq.select { |slug| @retrieval.roadmap(slug) }
            slugs.map { |slug| Prints.roadmap(@retrieval, slug) }.to_h { |print| [print.path, print] }
          end

          def on_disk
            files = @folders ? @folders.readable_files : @folder.intent_files
            [*(StoreFolder::INDEX if @folder.exist?(StoreFolder::INDEX)), *@folder.roadmap_files, *files]
          end
        end
      end
    end
  end
end
