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
            databases.fetch(:work).transaction { |batch| marks.each { |mark| write(batch, mark) } } if marks.any?
          end

          private

          def write(batch, mark)
            intent_id = mark["intent_id"]
            batch.put(:intents, Intent.from_h(Reader::IndexFile.intent_row(entries.fetch(intent_id))).new_row)
            batch.put(:archives, { intent_id:, at: mark["at"], restored_at: nil, session_id: mark["session_id"] })
            completion = mark["completion"]
            batch.put(:completions, completion_row(completion, intent_id)) if completion.is_a?(Hash)
          end

          def completion_row(completion, intent_id) = Work::CompletionRow.from_h(completion).to_h.except(:origin_id).merge(intent_id:)

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
