# frozen_string_literal: true

require "digest"
require "json"
require_relative "../invalid"
require_relative "edge"
require_relative "intent"
require_relative "node"
require_relative "savepoint"
require_relative "sql"
require_relative "store_folder"

module Plastic
  module Graph
    # Reads one file of a store folder into rows: the other half of Prints.
    # Each read is the statements it adds to a transaction of the database
    # that owns the file's rows, so the reads of one call commit together.
    class Reader
      # One file's read: the database it writes and the statements it adds.
      Read = Data.define(:path, :database, :apply)

      KEPT_MODE = 0o100644

      # `intents` maps each known intent id to its intent: from the rows and
      # from the store/index.json on disk.
      def initialize(folder, intents, origin_id)
        @folder = folder
        @intents = intents
        @origin_id = origin_id
      end

      def read(path)
        return Read.new(path, :work, ->(batch) { index(batch, path) }) if path == StoreFolder::INDEX

        intent = intent_of(path)
        rel = path.delete_prefix("#{intent.dir}/")
        database, kind = kind(rel, path)
        Read.new(path, database, ->(batch) { send(kind, batch, intent, rel, path) })
      end

      private

      def kind(rel, path)
        case rel
        when "graph.json" then %i[work graph]
        when "savepoint.md" then %i[work savepoint]
        else document?(rel, path) ? %i[knowledge document] : %i[references kept]
        end
      end

      def document?(rel, path) = rel.end_with?(".md") && !rel.start_with?("resources/") && text(path).valid_encoding?

      def text(path) = @folder.read(path).force_encoding(Encoding::UTF_8)

      def intent_of(path)
        dir = path.split("/").first(2).join("/")
        intent = @intents[File.basename(dir).split("--").first]
        return intent if intent&.dir == dir

        raise Invalid, "#{dir} has no intent row and no entry in #{StoreFolder::INDEX}; add one or remove the folder"
      end

      def index(batch, path)
        data = JSON.parse(text(path))
        Array(data["intents"]).each { |entry| batch.put(:intents, intent_row(entry)) }
        batch.remove(:clusters)
        Array(data["clusters"]).each do |cluster|
          cluster["intents"].each { |intent_id| batch.put(:clusters, { name: cluster["name"], intent_id: }) }
        end
      end

      def intent_row(entry)
        origin = entry["origin_id"]
        raise Invalid, "#{StoreFolder::INDEX} lists #{entry["intent_id"]} of origin #{origin}; a store holds only its own intents" unless origin == @origin_id

        Intent::INDEX_FIELDS.to_h { |field| [field, entry[field.to_s]] }.merge(updated_at: Plastic.now)
      end

      GRAPH_TABLES = { "nodes" => [:nodes, Node], "edges" => [:edges, Edge] }.freeze

      def graph(batch, intent, _rel, path)
        data = JSON.parse(text(path))
        id = intent.intent_id
        GRAPH_TABLES.each do |field, (table, record)|
          batch.remove(table, intent_id: id)
          Array(data[field]).each { |item| batch.put(table, record.from_h(item).with(intent_id: id).to_h.except(:origin_id)) }
        end
      end

      def savepoint(batch, intent, _rel, path)
        id = intent.intent_id
        batch.remove(:savepoints, intent_id: id)
        text(path).lines(chomp: true).each_with_index do |line, index|
          at, said = Savepoint.parse(line)
          batch.put(:savepoints, { intent_id: id, position: index + 1, at:, text: said })
        end
      end

      def document(batch, intent, rel, path)
        batch.put(:documents, { intent_id: intent.intent_id, path: rel, body: text(path), updated_at: Plastic.now })
      end

      def kept(batch, intent, _rel, path)
        bytes = @folder.read(path)
        batch.put(:sqlar, { name: path, mode: KEPT_MODE, mtime: File.mtime(@folder.path(path)).to_i, sz: bytes.bytesize,
                            data: SQL::Bytes.new(bytes), intent_id: intent.intent_id, sha256: Digest::SHA256.hexdigest(bytes) })
      end
    end
  end
end
