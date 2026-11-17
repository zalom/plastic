# frozen_string_literal: true

require "json"
require_relative "../../../invalid"

module Plastic
  module Graph
    module Knowledge
      class Reader
        # A context.json read for an intent that holds no context and no discovery: the two rows it carries.
        class ContextFile
          TABLES = { "discovery" => :retrieval_discoveries, "context" => :retrieval_contexts }.freeze

          def initialize(text, intent_id, path, clock:)
            @text = text
            @intent_id = intent_id
            @path = path
            @clock = clock
          end

          # Why the file cannot be read, or nil when it can.
          def problem
            data
            nil
          rescue Invalid => error
            error.message
          end

          # The rows by table, one for each part the file holds.
          def rows
            found = data
            TABLES.filter_map { |part, table| [table, row(found.fetch(part))] if found[part] }.to_h
          end

          private

          def data
            parsed = JSON.parse(@text)
            raise Invalid, "#{@path} is not a JSON object" unless parsed.is_a?(Hash)
            return parsed unless TABLES.keys.any? { |part| parsed[part] }

            raise Invalid, "#{@path} names intent #{parsed["intent"]}, not intent #{@intent_id}" unless parsed["intent"] == @intent_id

            parsed
          rescue JSON::ParserError
            raise Invalid, "#{@path} is not JSON"
          end

          def row(part) = { intent_id: @intent_id, data: JSON.pretty_generate(part), updated_at: Plastic.timestamp(@clock.now) }
        end
      end
    end
  end
end
