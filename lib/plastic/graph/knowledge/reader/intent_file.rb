# frozen_string_literal: true

require "digest"
require "json"
require_relative "../../retrieval/evidence/writer"
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
          KINDS = { "graph.json" => %i[work graph], "context.json" => %i[knowledge context], "work.log" => %i[work work_log],
                  "savepoint.md" => %i[work savepoint] }.freeze

          def initialize(file, intent_id, writer:, retrieval: nil)
            @file = file
            @intent_id = intent_id
            @writer = writer
            @retrieval = retrieval
          end

          def database = kind.first

          def apply(batch) = send(kind.last, batch)

          private

          def kind = KINDS.fetch(@file.rel) { text_kind }

          def text_kind
            return %i[references kept] unless document?

            LegacyPath.legacy?(@file.rel) ? %i[knowledge legacy] : %i[knowledge document]
          end

          def text = @file.bytes.force_encoding(Encoding::UTF_8)

          # Textual references are preserved in the knowledge graph. NUL bytes
          # identify binary data; invalid UTF-8 stays in the attachment archive.
          def document? = Retrieval::Evidence::Text.classify(@file.rel, @file.bytes) == :text

          def origin_id = @writer.origin_id

          def graph(batch) = GraphFile.new(text, @intent_id, origin_id, @file.path).apply(batch)

          # The rows of this home replace the rows of the file; the rows of another origin stay.
          def context(batch)
            rows = ContextFile.new(text, @intent_id, @file.path).rows
            ContextFile::TABLES.each_value { |table| batch.remove(table, intent_id: @intent_id) }
            rows.each { |table, row| batch.put(table, row) }
          end

          def work_log(batch)
            batch.remove(:work_log, intent_id: @intent_id)
            batch.put_all(:work_log, text.lines(chomp: true).reject { |line| line.strip.empty? }.each_with_index.map { |line, index| log_row(line, index) })
          end

          def log_row(line, index) = { intent_id: @intent_id, position: index + 1, **Work::LogLine.parse(line) }

          def savepoint(batch)
            known = Array(@retrieval&.work_log(@intent_id))
            seen = known.map(&:text)
            added = text.lines(chomp: true).reject { |line| line.strip.empty? }.filter_map { |line| old_row(line) }.reject { |row| seen.include?(row[:text]) }
            batch.put_all(:work_log, added.each_with_index.map { |row, index| { **row, position: known.size + index + 1 } })
          end

          def old_row(line)
            at, said = Work::Savepoint.parse(line)
            { intent_id: @intent_id, at:, kind: "noted", text: said }
          end

          def document(batch)
            @writer.apply(batch, @intent_id, @file.rel, text)
          end

          # The row replaces the document, head and search rows the path held before it was legacy.
          def legacy(batch)
            rel = @file.rel
            batch.put(:legacy_intents_data, { intent_id: @intent_id, path: rel, body: text, updated_at: Plastic.now })
            Retrieval::Evidence::Removal.new(batch, origin_id).remove(@intent_id, rel)
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
