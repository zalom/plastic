# frozen_string_literal: true

require_relative "../../../invalid"
require_relative "graph_file/document"
require_relative "graph_file/problems"

module Plastic
  module Graph
    module Knowledge
      class Reader
        # A graph.json view read back into the rows of its intent.
        class GraphFile
          def initialize(text, intent_id, origin_id, path)
            @document = Document.new(text)
            @intent_id = intent_id
            @origin_id = origin_id
            @path = path
          end

          def problems
            reasons = @document.valid? ? Problems.new(@document, @intent_id).call : ["is not valid JSON: #{@document.error}"]
            reasons.map { |reason| "#{@path} #{reason}" }
          end

          def apply(batch)
            refuse_problems
            Document::TABLES.each_key { |table| batch.remove(table, intent_id: @intent_id, origin_id: @origin_id) }
            rows.each { |table, list| batch.put_all(table, list) }
          end

          private

          def refuse_problems
            found = problems
            raise Invalid, found.join("; ") if found.any?
          end

          def rows = Document::TABLES.to_h { |table, record| [table, table_rows(table, record)] }

          def table_rows(table, record) = @document.records(table).map { |entry| row(record, entry) }

          def row(record, entry)
            keys = record.members - [:origin_id]
            keys.to_h { |key| [key, entry[key.to_s]] }.merge(intent_id: @intent_id, origin_id: @origin_id)
          end
        end
      end
    end
  end
end
