# frozen_string_literal: true

require "digest"
require "json"
require_relative "../../retrieval/evidence/document"
require_relative "../../retrieval/evidence/rows"
require_relative "../../retrieval/evidence/text"
require_relative "../../retrieval/evidence/removal"
require_relative "../legacy_path"
require_relative "folder_file"
require_relative "graph_file"
require_relative "context_file"
require_relative "../../work/edge"
require_relative "../../work/node"
require_relative "../../work/savepoint"
require_relative "../../work/log_line"
require_relative "../../sql"

module Plastic
  module Graph
    module Knowledge
      class Reader
        # One file of an intent folder and the rows it reads into: graph.json
        # into nodes and edges, work.log into work log lines, an old savepoint.md into noted lines, a Markdown
        # document into its row, a plan, checklist or action file into a legacy row,
        # and any other file kept whole as bytes.
        class IntentFile
          KEPT_MODE = 0o100644
          STAMPED = %i[context document legacy].freeze
          KINDS = { "graph.json" => :graph, "context.json" => :context, "work.log" => :work_log, "savepoint.md" => :savepoint }.freeze

          def initialize(file, intent_id, origin_id:, retrieval: nil)
            @file = file
            @intent_id = intent_id
            @origin_id = origin_id
            @retrieval = retrieval
          end

          def apply(batch, now)
            STAMPED.include?(kind) ? send(kind, batch, now:) : send(kind, batch)
            graph_file.apply_work(batch) if kind == :graph
          end

          private

          def kind = KINDS.fetch(@file.rel) { text_kind }

          def text_kind
            return :kept unless document?

            LegacyPath.legacy?(@file.rel) ? :legacy : :document
          end

          def text = @file.bytes.force_encoding(Encoding::UTF_8)

          # Textual references are preserved in the knowledge graph. NUL bytes
          # identify binary data; invalid UTF-8 stays in the attachment archive.
          def document? = Retrieval::Evidence::Text.classify(@file.rel, @file.bytes) == :text

          def graph(batch) = graph_file.apply(batch)

          def graph_file = GraphFile.new(text, @intent_id, @origin_id, @file.path)

          # The rows of this home replace the rows of the file; the rows of another origin stay.
          def context(batch, now:)
            rows = ContextFile.new(text, @intent_id, @file.path).rows(now)
            ContextFile::TABLES.each_value { |table| batch.remove(table, intent_id: @intent_id) }
            rows.each { |table, row| batch.put(table, row) }
          end

          def work_log(batch)
            batch.remove(:work_log, intent_id: @intent_id)
            batch.put_all(:work_log, text.lines(chomp: true).reject { |line| line.strip.empty? }.each_with_index.map { |line, index| log_row(line, index) })
          end

          def log_row(line, index) = { intent_id: @intent_id, position: index + 1, **Work::LogLine.parse(line) }

          def savepoint(batch)
            known = logged_lines
            added = old_rows.reject { |row| known.any? { |line| line.text == row[:text] } }
            start = known.map(&:position).max.to_i
            batch.put_all(:work_log, added.each_with_index.map { |row, index| { **row, position: start + index + 1 } })
          end

          def logged_lines = @retrieval.structure.work_log(@intent_id)

          def old_rows = text.lines(chomp: true).reject { |line| line.strip.empty? }.map { |line| old_row(line) }

          def old_row(line)
            at, said = Work::Savepoint.parse(line)
            { intent_id: @intent_id, at:, kind: "noted", text: said }
          end

          def document(batch, now:)
            document = Retrieval::Evidence::Document.new(@intent_id, @file.rel, text, now:)
            Retrieval::Evidence::Rows.new(batch, document, @origin_id).write
          end

          # The row replaces the document, head and search rows the path held before it was legacy.
          def legacy(batch, now:)
            rel = @file.rel
            batch.put(:legacy_intents_data, { intent_id: @intent_id, path: rel, body: text, updated_at: now })
            Retrieval::Evidence::Removal.new(batch, @origin_id).remove(@intent_id, rel)
          end

          def kept(batch)
            bytes = @file.bytes
            batch.put(:sqlar, { name: @file.path, mode: KEPT_MODE, mtime: @file.mtime,
                                sz: bytes.bytesize, data: SQLite3::Blob.new(bytes), intent_id: @intent_id,
                                sha256: Digest::SHA256.hexdigest(bytes) })
          end
        end
      end
    end
  end
end
