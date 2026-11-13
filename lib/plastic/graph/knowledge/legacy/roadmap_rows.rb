# frozen_string_literal: true

require_relative "../roadmap/parse"
require_relative "savepoint_log"

module Plastic
  module Graph
    module Knowledge
      module Legacy
        # Writes the rows of one parsed legacy roadmap into the work graph.
        class RoadmapRows
          NO_GOAL = { goal: nil, done: [] }.freeze

          def initialize(graphs, slug, result)
            @graphs = graphs
            @slug = slug
            @result = result
          end

          def call(savepoint)
            write_batches
            write_items
            write_edges
            write_log(@result.log + SavepointLog.new(savepoint).lines)
            write_header
          end

          private

          # A roadmap with no batch headings lists its items in one batch.
          def write_batches
            batches = @result.batches
            batches = [Roadmap::Parse::Batch.new(position: 1, title: @result.title)] if batches.empty?
            batches.each { |batch| @graphs.work.write_batch(@slug, batch.position, fields: Roadmap::Writer::Fields.new(title: batch.title, **NO_GOAL)) }
          end

          def write_items = @result.items.each { |item| add_item(item) }

          # An imported item keys by its intent id, so it names that intent when the store holds one.
          def add_item(item)
            id = item.item
            work = @graphs.work
            work.add_item(@slug, id, item.batch || 1, fields: Roadmap::Writer::Fields.new(title: item.title, **NO_GOAL), needs: [])
            work.open_item(@slug, id, id) if @graphs.retrieval.intent(id)
          end

          def write_edges
            edge_rows.each { |row| insert(:roadmap_edges, row) }
          end

          def edge_rows = @result.edges.flat_map { |to, froms| edges_to(to, froms) }

          def edges_to(to, froms) = froms.map { |from| { roadmap: @slug, from:, to:, kind: "after" } }

          def write_log(log)
            log.each_with_index { |line, index| insert(:roadmap_log, log_row(line, index + 1)) }
          end

          def log_row(line, position) = line.to_h.merge(roadmap: @slug, position:, session_id: nil)

          def write_header
            put(:roadmaps, { slug: @slug, title: @result.title, goal: @result.goal }, :upsert)
          end

          def insert(table, row) = put(table, row, :insert)

          def put(table, row, statement)
            @graphs.databases.fetch(:work).transaction { |batch| batch.put(table, row, statement:) }
          end
        end
      end
    end
  end
end
