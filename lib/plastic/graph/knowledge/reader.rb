# frozen_string_literal: true

require_relative "../../invalid"
require_relative "reader/index_file"
require_relative "reader/intent_file"
require_relative "../prints"
require_relative "store_folder"

module Plastic
  module Graph
    module Knowledge
      # Reads one file of a store folder into rows: the other half of Prints.
      # Each read is the statements it adds to a transaction of the database
      # that owns the file's rows, so the reads of one call commit together.
      class Reader
        # One file's read: the database it writes and the statements it adds.
        Read = Data.define(:path, :database, :apply)

        # A read file and the print that keeps it.
        class Read
          # A file whose rows print nothing, such as an empty savepoint.md, keeps its own hash.
          def line = "read #{path}"

          def kept_print(folder) = Prints::Print.new(path, database, folder.digest(path), nil)
        end

        # `intents` maps each known intent id to its intent: from the rows and
        # from the store/index.json on disk.
        def initialize(folder, intents, origin_id, retrieval: nil, heads: Retrieval::Evidence::Heads::Unread.new)
          @folder = folder
          @intents = intents
          @retrieval = retrieval
          @writer = Retrieval::Evidence::Writer.new(nil, origin_id, heads:)
        end

        def read(path)
          file = (path == StoreFolder::INDEX) ? IndexFile.new(@folder.read(path), @writer.origin_id) : intent_file(path)
          Read.new(path, file.database, file.method(:apply))
        end

        private

        def intent_file(path)
          dir = path.split("/").first(2).join("/")
          intent = @intents[File.basename(dir).split("--").first]
          return intent_file_of(intent, path) if intent&.dir == dir

          raise Invalid, "#{dir} has no intent row and no entry in #{StoreFolder::INDEX}; add one or remove the folder"
        end

        def intent_file_of(intent, path)
          file = FolderFile.new(@folder, path, path.delete_prefix("#{intent.dir}/"))
          IntentFile.new(file, intent.intent_id, retrieval: @retrieval, writer: @writer)
        end
      end
    end
  end
end
