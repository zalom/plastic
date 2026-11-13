# frozen_string_literal: true

require "json"
require_relative "../intent"
require_relative "../reader/index_file"
require_relative "../store_folder"
require_relative "archived_intents/mark"

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
