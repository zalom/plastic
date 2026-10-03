# frozen_string_literal: true

require "digest"
require "json"
require_relative "../evidence_writer"
require_relative "../evidence_text"
require_relative "folder_file"
require_relative "../edge"
require_relative "../node"
require_relative "../savepoint"
require_relative "../sql"

module Plastic
  module Graph
    class Reader
      # One file of an intent folder and the rows it reads into: graph.json
      # into nodes and edges, savepoint.md into savepoint lines, a Markdown
      # document into its row, and any other file kept whole as bytes.
      class IntentFile
        KEPT_MODE = 0o100644
        KINDS = { "graph.json" => %i[work graph], "savepoint.md" => %i[work savepoint] }.freeze

        def initialize(folder, intent, path, origin_id, retrieval: nil)
          @file = FolderFile.new(folder, path, path.delete_prefix("#{intent.dir}/"))
          @intent_id = intent.intent_id
          @origin_id = origin_id
          @retrieval = retrieval
        end

        def database = kind.first

        def apply(batch) = send(kind.last, batch)

        private

        def kind = KINDS.fetch(@file.rel) { document? ? %i[knowledge document] : %i[references kept] }

        def text = @file.bytes.force_encoding(Encoding::UTF_8)

        # Textual references are preserved in the knowledge graph. NUL bytes
        # identify binary data; invalid UTF-8 stays in the attachment archive.
        def document? = EvidenceText.classify(@file.rel, @file.bytes) == :text

        def graph(_batch)
          raise Invalid, "graph.json is generated from rows; use node and edge commands to change the graph"
        end

        def savepoint(batch)
          previous = Array(@retrieval&.savepoints(@intent_id)).group_by(&:line)
          batch.remove(:savepoints, intent_id: @intent_id)
          batch.put_all(:savepoints, text.lines(chomp: true).each_with_index.map { |line, index| savepoint_row(line, index, previous) })
        end

        def savepoint_row(line, index, previous_lines)
          at, said = Savepoint.parse(line)
          previous = previous_lines.fetch(line, []).shift
          { intent_id: @intent_id, position: index + 1, at:, text: said, session_id: previous&.session_id }
        end

        def document(batch)
          EvidenceWriter.new(nil, @origin_id).apply(batch, @intent_id, @file.rel, text)
        end

        def kept(batch)
          bytes = @file.bytes
          batch.put(:sqlar, { name: @file.path, mode: KEPT_MODE, mtime: @file.mtime,
                              sz: bytes.bytesize, data: SQL::Bytes.new(bytes), intent_id: @intent_id,
                              sha256: Digest::SHA256.hexdigest(bytes) })
        end
      end
    end
  end
end
