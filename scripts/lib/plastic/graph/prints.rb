# frozen_string_literal: true

require "digest"
require "json"
require_relative "intent"
require_relative "store_folder"
require_relative "roadmap_state"

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
        Print.text(StoreFolder::INDEX, :work, "#{JSON.pretty_generate(data)}\n")
      end

      def clusters(rows)
        rows.group_by(&:name).map { |name, members| { "name" => name, "intents" => luhmann(members.map(&:intent_id)) } }
      end

      def luhmann(ids) = ids.sort_by { |id| LuhmannId.segments(id) }

      # Every file of the store, read in five queries whatever the number of intents.
      def of_store(retrieval)
        rows = Contents.read(retrieval)
        [index(retrieval), *retrieval.unarchived_intents.flat_map { |intent| of_intent(retrieval, intent, rows) }]
      end

      def of_intent(retrieval, intent, rows = nil)
        id = intent.intent_id
        rows ||= Contents.read(retrieval, id)
        [*documents(intent, rows.documents(id)), *savepoint(intent, rows.savepoints(id)),
          graph(intent, rows.nodes(id), rows.edges(id)), *kept_files(retrieval, rows.kept_files(id))]
      end

      def documents(intent, rows) = rows.map { |document| Print.text("#{intent.dir}/#{document.path}", :knowledge, document.body) }

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

      def roadmap(retrieval, slug)
        row = retrieval.roadmap(slug)
        lines = ["# #{row.title}", "", *goal_lines(row.goal), *roadmap_batches(retrieval, slug),
          "## Graph", "", *roadmap_edge_lines(retrieval, slug), "", "## Log", "", *roadmap_log_lines(retrieval, slug)]
        Print.text("roadmaps/#{slug}.md", :work, "#{lines.join("\n")}\n")
      end

      def goal_lines(goal) = goal ? ["## Goal", "", goal, ""] : []

      def roadmap_batches(retrieval, slug)
        retrieval.batches(slug).flat_map { |batch| roadmap_batch_lines(retrieval, slug, batch) }
      end

      def roadmap_batch_lines(retrieval, slug, batch)
        items = retrieval.roadmap_items(slug).select { |item| item.batch == batch.position }
        ["## Batch #{batch.position}: #{batch.title}", "", *batch.done_lines.map { |line| "- #{line}" }, "",
          *items.map { |item| roadmap_item_line(item, retrieval) }, ""]
      end

      def roadmap_item_line(item, retrieval)
        state = RoadmapState.of(item, retrieval)
        mark = (state == "done" || state == "dropped") ? "x" : " "
        "- [#{mark}] #{item.item} #{item.title} — #{state}"
      end

      def roadmap_edge_lines(retrieval, slug)
        retrieval.roadmap_items(slug).map do |item|
          from = retrieval.roadmap_edges(slug).select { |edge| edge.to == item.item }.map(&:from)
          "- #{item.item} needs #{from.empty? ? "nothing" : from.join(" ")}"
        end
      end

      def roadmap_log_lines(retrieval, slug)
        retrieval.roadmap_log(slug).map { |line| "- #{line.at} #{line.text}" }
      end

      # The rows of one intent or of the whole store, grouped by intent.
      Contents = Data.define(:groups)

      # The rows of each table, by intent.
      class Contents
        def self.read(retrieval, intent_id = nil)
          tables = %i[documents savepoints nodes edges kept_files]
          new(tables.to_h { |table| [table, retrieval.public_send(table, intent_id).group_by(&:intent_id)] })
        end

        %i[documents savepoints nodes edges kept_files].each do |table|
          define_method(table) { |intent_id| groups.fetch(table).fetch(intent_id, []) }
        end
      end
    end
  end
end
