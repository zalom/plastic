# frozen_string_literal: true

require "digest"
require "json"
require_relative "knowledge/intent"
require_relative "knowledge/store_folder"
require_relative "roadmap_print"

module Plastic
  module Graph
    # The files printed from a store's rows, each with the database that
    # owns its rows. Paths are relative to the store folder:
    #
    # - store/index.json lists this installation's intents and the clusters.
    # - store/ID--SLUG/PATH is a document, byte for byte.
    # - store/ID--SLUG/savepoint.md holds the savepoint lines.
    # - store/ID--SLUG/graph.json holds the nodes and edges.
    # - any other file of the folder is a kept file, from the SQL archive.
    #
    # The same rows always print the same bytes, so a hash tells whether a
    # file or its rows changed since the last print.
    module Prints
      # One file and how to make it. `source` gives the bytes only when the
      # file must be written, so a kept file is compared by its hash alone.
      Print = Data.define(:path, :database, :sha256, :source)

      # How a print compares with its file and its record.
      class Print
        def self.text(path, database, text) = new(path, database, Digest::SHA256.hexdigest(text), -> { text })

        def text = source.call

        # The file holds these bytes already.
        def level?(folder) = folder.digest(path) == sha256

        def write_to(folder) = folder.write(path, text)

        # The last print recorded these bytes.
        def recorded?(recorded) = recorded[path] == sha256

        def printed_row = { path:, sha256:, at: Plastic.now }
      end

      module_function

      def index(retrieval)
        data = { "store" => retrieval.store, "origin_id" => retrieval.origin_id,
                 "intents" => retrieval.unarchived_intents.map(&:index_h), "clusters" => clusters(retrieval.clusters) }
        Print.text(Knowledge::StoreFolder::INDEX, :work, "#{JSON.pretty_generate(data)}\n")
      end

      def clusters(rows)
        rows.group_by(&:name).map { |name, members| { "name" => name, "intents" => luhmann(members.map(&:intent_id)) } }
      end

      def luhmann(ids) = ids.sort_by { |id| Knowledge::LuhmannId.segments(id) }

      # Every file of the store, read in six queries whatever the number of intents.
      def of_store(retrieval)
        rows = Contents.read(retrieval)
        [index(retrieval), *retrieval.unarchived_intents.flat_map { |intent| of_intent(retrieval, intent, rows) }]
      end

      def of_intent(retrieval, intent, rows = nil)
        id = intent.intent_id
        rows ||= Contents.read(retrieval, id)
        legacy = rows.legacy_intents_data(id)
        dir = intent.dir
        [*documents(dir, rows.documents(id), legacy), *text_files(dir, legacy), *savepoint(intent, rows.savepoints(id)),
          graph(intent, rows.nodes(id), rows.edges(id)), *kept_files(retrieval, rows.kept_files(id))]
      end

      # A path held as a legacy row and as a document prints from the legacy row only.
      def documents(dir, rows, legacy)
        held = legacy.map(&:path)
        text_files(dir, rows.reject { |document| held.include?(document.path) })
      end

      def text_files(dir, rows) = rows.map { |row| Print.text("#{dir}/#{row.path}", :knowledge, row.body) }

      # A kept file is compared by its hash; its bytes are read only to write it.
      def kept_files(retrieval, rows)
        rows.map do |kept|
          name = kept.name
          Print.new(name, :references, kept.sha256, -> { retrieval.kept_file_data(name) })
        end
      end

      def savepoint(intent, lines)
        return [] if lines.empty?

        [Print.text("#{intent.dir}/savepoint.md", :work, lines.map { |line| "#{line.line}\n" }.join)]
      end

      def graph(intent, nodes, edges)
        data = { "intent" => intent.intent_id, "nodes" => nodes.map { |node| plain(node) }, "edges" => edges.map { |edge| plain(edge) } }
        Print.text("#{intent.dir}/graph.json", :work, "#{JSON.pretty_generate(data)}\n")
      end

      def plain(record) = record.to_h.except(:origin_id).transform_keys(&:to_s)

      def roadmap(retrieval, slug) = Print.text("roadmaps/#{slug}.md", :work, RoadmapPrint.new(retrieval, slug).text)

      # The rows of one intent or of the whole store, grouped by intent.
      Contents = Data.define(:groups)

      # The rows of each table, by intent.
      class Contents
        TABLES = %i[documents legacy_intents_data savepoints nodes edges kept_files].freeze

        def self.read(retrieval, intent_id = nil)
          new(TABLES.to_h { |table| [table, retrieval.public_send(table, intent_id).group_by(&:intent_id)] })
        end

        TABLES.each do |table|
          define_method(table) { |intent_id| groups.fetch(table).fetch(intent_id, []) }
        end
      end
    end
  end
end
