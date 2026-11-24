# frozen_string_literal: true

require "digest"
require "json"
require_relative "../../evidence/text"
require_relative "../legacy_path"
require_relative "folder_file"
require_relative "graph_file"
require_relative "context_file"
require_relative "log_file"
require_relative "text_file"
require_relative "../../sql"
require_relative "../../../layout"

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
          KINDS = { Layout.name(:graph) => :graph, Layout.name(:context) => :context, Layout.name(:log) => :work_log }.freeze

          def initialize(file, intent_id, origin_id:, retrieval: nil)
            @file = file
            @intent_id = intent_id
            @origin_id = origin_id
            @retrieval = retrieval
          end

          def apply(batch, now)
            found = kind
            case found
            when :context then context(batch, now)
            when :document, :legacy then text_file(now).public_send(found, batch)
            else send(found, batch)
            end
            graph_file.apply_work(batch) if found == :graph
          end

          private

          def kind = KINDS.fetch(@file.rel) { text_kind }

          def text_kind
            return :kept unless document?
            return :savepoint if Layout.legacy_sync(@file.rel) == "lines"

            LegacyPath.legacy?(@file.rel) ? :legacy : :document
          end

          def text = @file.bytes.force_encoding(Encoding::UTF_8)

          # Textual references are preserved in the knowledge graph. NUL bytes
          # identify binary data; invalid UTF-8 stays in the attachment archive.
          def document? = Retrieval::Evidence::Text.classify(@file.rel, @file.bytes) == :text

          def graph(batch) = graph_file.apply(batch)

          def graph_file = GraphFile.new(text, @intent_id, @origin_id, @file.path)

          # The rows of this home replace the rows of the file; the rows of another origin stay.
          def context(batch, now)
            rows = ContextFile.new(text, @intent_id, @file.path).rows(now)
            ContextFile::TABLES.each_value { |table| batch.remove(table, intent_id: @intent_id) }
            rows.each { |table, row| batch.put(table, row) }
          end

          def work_log(batch) = LogFile.new(text, @intent_id).work_log(batch)

          def savepoint(batch) = LogFile.new(text, @intent_id).savepoint(batch, @retrieval.structure.work_log(@intent_id))

          def text_file(now) = TextFile.new(TextFile::Subject.new(@intent_id, @file.rel, text, now), @origin_id)

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
