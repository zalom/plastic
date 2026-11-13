# frozen_string_literal: true

require "json"
require_relative "../intent"
require_relative "../reader/index_file"
require_relative "../store_folder"

module Plastic
  module Graph
    module Knowledge
      class Sync
        # The archived intents that store/index.json lists and this installation has no row for: each gets
        # its intent, its archive mark and its completion, and a row already held is never replaced.
        class ArchivedIntents
          # One archive entry of the index with the index entry of its intent: the rows they stand for.
          Mark = Data.define(:fields, :entry) do
            def intent_id = fields["intent_id"]

            def intent_row = Intent.from_h(Reader::IndexFile.intent_row(entry)).new_row

            def archive_row = { intent_id:, at: fields["at"], restored_at: nil, session_id: fields["session_id"] }

            def completion_rows = [fields["completion"]].grep(Hash).map { |hash| Work::CompletionRow.stored(hash, intent_id) }

            def put_all(batch)
              batch.put(:intents, intent_row)
              batch.put(:archives, archive_row)
              completion_rows.each { |row| batch.put(:completions, row) }
            end
          end

          def initialize(folder, retrieval)
            @folder = folder
            @retrieval = retrieval
          end

          def missing
            held = @retrieval.intents.map(&:intent_id)
            archives.reject { |mark| held.include?(mark["intent_id"]) }
          end

          def write_to(databases)
            marks = missing
            databases.fetch(:work).transaction { |batch| write_all(batch, marks) } if marks.any?
          end

          private

          def write_all(batch, marks) = marks.each { |mark| write(batch, mark) }

          def write(batch, mark)
            Mark.new(mark, entries.fetch(mark["intent_id"])).put_all(batch)
          end

          def archives = Array(data["archives"]).grep(Hash).select { |mark| entries.key?(mark["intent_id"]) }

          def entries = (@entries ||= Array(data["intents"]).grep(Hash).to_h { |entry| [entry["intent_id"], entry] })

          def data = (@data ||= parsed)

          def parsed
            return {} unless @folder.exist?(StoreFolder::INDEX)

            JSON.parse(@folder.read(StoreFolder::INDEX).force_encoding(Encoding::UTF_8)).then { |data| data.is_a?(Hash) ? data : {} }
          rescue JSON::ParserError
            {}
          end
        end
      end
    end
  end
end
