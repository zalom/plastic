# frozen_string_literal: true

require_relative "../roadmap/parse"
require_relative "originals"

module Plastic
  module Graph
    module Knowledge
      module Legacy
        # Imports roadmap batches, items, edges, and history from legacy files.
        class Roadmaps
          def parse(root)
            roadmap_files(root).to_h do |path|
              [path, Roadmap::Parse.call(File.read(path, encoding: "UTF-8"), path: relative(root, path))]
            end
          end

          def relative(root, path) = path.delete_prefix("#{root}/")

          def roadmap_files(root) = Dir.glob(File.join(root, "roadmaps", "{,archived/}*.md")).reject { |path| path.end_with?(".savepoint.md") }.sort

          def migrate_roadmaps(graphs, root, parsed, counts)
            parsed.each do |path, result|
              slug = File.basename(path, ".md")
              original_bytes = File.binread(path)
              write_roadmap_rows(graphs, slug, result, path.sub(/\.md\z/, ".savepoint.md"))
              graphs.work.print_roadmap(slug)
              Originals.new.keep_roadmap_original(graphs.databases, root, slug, original_bytes, counts)
              counts[:roadmaps] += 1
              counts[:roadmap_items] += result.items.size
            end
          end

          # A roadmap with no batch headings lists its items in one batch.
          def write_roadmap_rows(graphs, slug, result, savepoint)
            databases = graphs.databases
            write_batches(graphs.work, slug, result)
            result.items.each { |item| add_item(graphs, slug, item, fields(item.title)) }
            write_edges(databases, slug, result.edges)
            write_log(databases, slug, result.log + savepoint_log(savepoint))
            write_header(databases, slug, result)
          end

          def fields(title) = Roadmap::Writer::Fields.new(title:, goal: nil, done: [])

          def write_batches(work, slug, result)
            batches = result.batches.empty? ? [Roadmap::Parse::Batch.new(position: 1, title: result.title)] : result.batches
            batches.each { |batch| work.write_batch(slug, batch.position, fields: fields(batch.title)) }
          end

          def write_header(databases, slug, result)
            databases.fetch(:work).transaction { |batch| batch.put(:roadmaps, { slug:, title: result.title, goal: result.goal }, statement: :upsert) }
          end

          # An imported item keys by its intent id, so it names that intent when the store holds one.
          def add_item(graphs, slug, item, fields)
            id = item.item
            graphs.work.add_item(slug, id, item.batch || 1, fields:, after: [])
            graphs.work.start_item(slug, id, id) if graphs.retrieval.intent(id)
          end

          # The `.savepoint.md` sibling: one line per event, its time stamp first.
          def savepoint_log(path)
            return [] unless File.exist?(path)

            File.read(path, encoding: "UTF-8").each_line.filter_map do |line|
              at, text = line.strip.split(/\s+/, 2)
              Roadmap::Parse::LogLine.new(at:, text: text.to_s.squeeze(" ")) if at
            end
          end

          def write_edges(databases, slug, edges)
            database = databases.fetch(:work)
            edges.each do |to, froms|
              froms.each { |from| database.transaction { |batch| batch.put(:roadmap_edges, { roadmap: slug, from:, to:, kind: "after" }, statement: :insert) } }
            end
          end

          def write_log(databases, slug, log)
            database = databases.fetch(:work)
            log.each_with_index do |line, index|
              row = { roadmap: slug, position: index + 1, at: line.at, text: line.text, session_id: @session }
              database.transaction { |batch| batch.put(:roadmap_log, row, statement: :insert) }
            end
          end
        end
      end
    end
  end
end
