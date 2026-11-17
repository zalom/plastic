# frozen_string_literal: true

require_relative "../../invalid"
require_relative "reader/index_file"
require_relative "reader/cluster_file"
require_relative "reader/link_file"
require_relative "reader/intent_file"
require_relative "reader/roadmap_file"
require_relative "../prints"
require_relative "store_folder"
require_relative "store_path"

module Plastic
  module Graph
    module Knowledge
      # Reads one file of a store folder into rows: the other half of Prints.
      # Each read is the statements it adds to a transaction of the database
      # of the store, so the reads of one call commit together.
      class Reader
        # One file's read: the statements it adds to a transaction.
        Read = Data.define(:path, :apply)

        # A read file and the print that keeps it.
        class Read
          # A file whose rows print nothing, such as an empty work.log, keeps its own hash.
          def line = "read #{path}"

          def kept_print(folder) = Prints::Print.new(path, folder.digest(path), nil)
        end

        # The reader of the intents of the rows.
        def self.of(folder, retrieval, **options)
          known = retrieval.intents.to_h { |intent| [intent.intent_id, intent] }
          new(folder, known, retrieval.origin_id, retrieval:, **options)
        end

        # `intents` maps each known intent id to its intent: from the rows and
        # from the store/index.json on disk.
        def initialize(folder, intents, origin_id, retrieval: nil)
          @folder = folder
          @intents = intents
          @retrieval = retrieval
          @origin_id = origin_id
        end

        def read(path, now)
          file = file_of(path)
          Read.new(path, ->(batch) { file.apply(batch, now) })
        end

        private

        def file_of(path)
          return index_file(path) if path == StoreFolder::INDEX
          return part_file(path) if Prints::Parts.path?(path)
          return roadmap_file(path) if StorePath.roadmap?(path)

          intent_file(path)
        end

        def index_file(path) = IndexFile.new(@folder.read(path), @origin_id, @folder.intent_dirs, @intents)

        def roadmap_file(path) = RoadmapFile.new(File.basename(path, ".md"), @folder.read(path))

        def part_file(path)
          index = @folder.read(StoreFolder::INDEX)
          return ClusterFile.new(index, @origin_id) if Prints::ClusterPart.path?(path)

          LinkFile.new(index, @origin_id, printed?(path))
        end

        # A part with a printed row has a last print to judge a removal against.
        def printed?(path) = !@retrieval.nil? && @retrieval.stored.printed.key?(path)

        def intent_file(path)
          dir = path.split("/").first(2).join("/")
          intent = @intents[File.basename(dir).split("--").first]
          return intent_file_of(intent, path) if intent&.dir == dir

          raise Invalid, "#{dir} has no intent row and no entry in #{StoreFolder::INDEX}; add one or remove the folder"
        end

        def intent_file_of(intent, path)
          file = FolderFile.new(@folder, path, path.delete_prefix("#{intent.dir}/"))
          IntentFile.new(file, intent.intent_id, retrieval: @retrieval, origin_id: @origin_id)
        end
      end
    end
  end
end
